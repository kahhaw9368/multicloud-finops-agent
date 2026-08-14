"""
AWS CloudWatch Metrics MCP Server - Lambda Implementation for Amazon Bedrock AgentCore Gateway

Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
SPDX-License-Identifier: MIT-0

Why a custom Lambda rather than the awslabs CloudWatch MCP server:

The awslabs server (awslabs.cloudwatch-mcp-server) ships as a **stdio** transport for
local clients (Q CLI, Kiro, Claude Code). Amazon Quick Suite requires remote HTTP -
"Local stdio connections are not supported". Hosting it would mean a container image,
an AgentCore Runtime and a Lambda proxy: exactly the dependency chain removed from this
project along with the aws-api-mcp target. It also carries alarm-troubleshooting and
log-analysis tools this FinOps use case does not need.

This reads the **CloudWatch Metrics API**, not Container Insights specifically.
ContainerInsights is simply the first namespace it is pointed at; the same tools read
AWS/EC2, AWS/RDS, AWS/Lambda or any custom namespace.

Tools:
- list_metrics:    discover metrics and their dimensions in a namespace
- get_metric_data: retrieve datapoints, including metric-math expressions

Metric math is the important capability. Container Insights exposes pod_cpu_request and
pod_cpu_usage_total but NOT a ready-made "utilization over request" metric
(pod_cpu_utilization_over_pod_limit exists; over_pod_request does not). So the
rightsizing ratio must be computed - and GetMetricData does it server-side:

    m1 = pod_cpu_usage_total
    m2 = pod_cpu_request
    e1 = m1/m2*100          <- percent of requested CPU actually used

Architecture:
    Client (Quick Suite) -> Gateway (OAuth+MCP) -> Lambda (JSON) -> CloudWatch API

Required IAM Permissions:
- cloudwatch:ListMetrics
- cloudwatch:GetMetricData
(Neither supports resource-level scoping.)
"""

import json
import re
from datetime import datetime, timedelta

import boto3

# GetMetricData hard limits (AWS service quotas)
MAX_QUERIES = 500
MAX_DATAPOINTS = 100_800
DEFAULT_PERIOD = 3600
DEFAULT_STAT = "Average"

VALID_STATS = {
    "Average",
    "Sum",
    "Minimum",
    "Maximum",
    "SampleCount",
}

# Statistics of the form p95, p99.9, tm90, etc. are also valid
EXTENDED_STAT_PATTERN = re.compile(r"^(p|tm|tc|ts|wm)\d{1,2}(\.\d{1,2})?$")

ISO_PATTERN = re.compile(r"^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}:\d{2}Z?)?$")

# Identifier rules for GetMetricData Id fields
ID_PATTERN = re.compile(r"^[a-z][a-zA-Z0-9_]*$")


def _cw():
    return boto3.client("cloudwatch")


def validate_stat(stat):
    """Accept the five standard statistics plus extended percentile forms."""
    if stat in VALID_STATS or EXTENDED_STAT_PATTERN.match(stat or ""):
        return stat
    raise ValueError(
        f"Invalid statistic '{stat}'. Use one of {sorted(VALID_STATS)} "
        "or an extended statistic such as p95, p99, tm90."
    )


def validate_time(value, param_name):
    """Validate an ISO-8601 date or datetime and return it unchanged."""
    if not value:
        raise ValueError(f"{param_name} is required")
    if not ISO_PATTERN.match(value):
        raise ValueError(
            f"{param_name} must be YYYY-MM-DD or YYYY-MM-DDTHH:MM:SSZ, got '{value}'"
        )
    return value


def _parse_time(value):
    """Parse the validated string into a datetime for boto3."""
    if len(value) == 10:
        return datetime.strptime(value, "%Y-%m-%d")
    return datetime.strptime(value.rstrip("Z"), "%Y-%m-%dT%H:%M:%S")


def _dimensions(raw):
    """Normalise dimensions from either a dict or a list of {Name,Value}."""
    if not raw:
        return []
    if isinstance(raw, dict):
        return [{"Name": k, "Value": v} for k, v in raw.items()]
    out = []
    for d in raw:
        name = d.get("Name") or d.get("name")
        value = d.get("Value") or d.get("value")
        if name is None or value is None:
            raise ValueError(f"Each dimension needs Name and Value, got {d}")
        out.append({"Name": name, "Value": value})
    return out


def lambda_handler(event, context):
    """
    Main Lambda handler for Gateway MCP tools.

    Gateway passes tool name via context.client_context.custom["bedrockAgentCoreToolName"]
    in format: <target_name>___<tool_name>
    """
    print(f"Event: {json.dumps(event)}")

    extended_tool_name = context.client_context.custom["bedrockAgentCoreToolName"]
    tool_name = extended_tool_name.split("___")[1]

    print(f"Tool name: {tool_name}")

    handlers = {
        "list_metrics": handle_list_metrics,
        "get_metric_data": handle_get_metric_data,
    }

    handler = handlers.get(tool_name)
    if handler:
        try:
            return handler(event)
        except ValueError as exc:
            return {"error": str(exc)}
    return {"error": f"Unknown tool: {tool_name}", "available_tools": list(handlers.keys())}


def handle_list_metrics(event):
    """
    Discover metrics in a namespace, optionally filtered by metric name and dimensions.

    Returns the distinct dimension values found, which is usually what the caller needs
    in order to build a get_metric_data request.
    """
    namespace = event.get("namespace")
    if not namespace:
        raise ValueError("namespace is required, e.g. 'ContainerInsights' or 'AWS/EC2'")

    kwargs = {"Namespace": namespace}
    if event.get("metric_name"):
        kwargs["MetricName"] = event["metric_name"]
    if event.get("dimensions"):
        kwargs["Dimensions"] = _dimensions(event["dimensions"])

    max_results = int(event.get("max_results") or 300)

    cw = _cw()
    metrics, token, pages = [], None, 0
    while True:
        if token:
            kwargs["NextToken"] = token
        resp = cw.list_metrics(**kwargs)
        metrics.extend(resp.get("Metrics", []))
        token = resp.get("NextToken")
        pages += 1
        if not token or len(metrics) >= max_results or pages >= 10:
            break

    metrics = metrics[:max_results]

    # Summarise: metric names present, and the distinct values per dimension key
    names = sorted({m["MetricName"] for m in metrics})
    dim_values = {}
    for m in metrics:
        for d in m.get("Dimensions", []):
            dim_values.setdefault(d["Name"], set()).add(d["Value"])

    return {
        "namespace": namespace,
        "metric_count": len(metrics),
        "metric_names": names,
        "dimensions": {k: sorted(v)[:100] for k, v in sorted(dim_values.items())},
        "truncated": bool(token),
    }


def handle_get_metric_data(event):
    """
    Retrieve metric datapoints. Supports metric math, which is how ratios such as
    "percent of requested CPU actually used" are computed server-side.

    Two input styles:

    1. Simple - one metric:
       {"namespace": "...", "metric_name": "...", "dimensions": {...},
        "start_time": "...", "end_time": "...", "period": 3600, "stat": "Average"}

    2. Advanced - explicit queries, enabling metric math:
       {"queries": [
          {"id": "m1", "namespace": "ContainerInsights",
           "metric_name": "pod_cpu_usage_total",
           "dimensions": {"ClusterName": "x", "PodName": "y", "Namespace": "z"},
           "stat": "Average", "period": 3600, "return_data": false},
          {"id": "m2", "namespace": "ContainerInsights",
           "metric_name": "pod_cpu_request", "dimensions": {...},
           "stat": "Average", "period": 3600, "return_data": false},
          {"id": "e1", "expression": "m1/m2*100", "label": "pct_of_request"}
        ],
        "start_time": "...", "end_time": "..."}
    """
    start = validate_time(event.get("start_time"), "start_time")
    end = validate_time(event.get("end_time"), "end_time")
    start_dt, end_dt = _parse_time(start), _parse_time(end)
    if start_dt >= end_dt:
        raise ValueError("start_time must be earlier than end_time")

    queries = event.get("queries")

    if not queries:
        namespace = event.get("namespace")
        metric_name = event.get("metric_name")
        if not namespace or not metric_name:
            raise ValueError(
                "Provide either 'queries', or both 'namespace' and 'metric_name'"
            )
        queries = [
            {
                "id": "m1",
                "namespace": namespace,
                "metric_name": metric_name,
                "dimensions": event.get("dimensions"),
                "stat": event.get("stat", DEFAULT_STAT),
                "period": event.get("period", DEFAULT_PERIOD),
                "return_data": True,
            }
        ]

    if len(queries) > MAX_QUERIES:
        raise ValueError(f"At most {MAX_QUERIES} queries per call, got {len(queries)}")

    data_queries = []
    for q in queries:
        qid = q.get("id")
        if not qid or not ID_PATTERN.match(qid):
            raise ValueError(
                f"Query id '{qid}' must start with a lowercase letter and contain only "
                "letters, digits and underscores"
            )

        entry = {"Id": qid}
        if q.get("label"):
            entry["Label"] = q["label"]
        # return_data defaults True for expressions, False for raw metrics feeding them
        entry["ReturnData"] = bool(q.get("return_data", "expression" in q))

        if q.get("expression"):
            entry["Expression"] = q["expression"]
            if q.get("period"):
                entry["Period"] = int(q["period"])
        else:
            if not q.get("namespace") or not q.get("metric_name"):
                raise ValueError(
                    f"Query '{qid}' needs either 'expression', or 'namespace' and 'metric_name'"
                )
            entry["MetricStat"] = {
                "Metric": {
                    "Namespace": q["namespace"],
                    "MetricName": q["metric_name"],
                    "Dimensions": _dimensions(q.get("dimensions")),
                },
                "Period": int(q.get("period", DEFAULT_PERIOD)),
                "Stat": validate_stat(q.get("stat", DEFAULT_STAT)),
            }
        data_queries.append(entry)

    cw = _cw()
    kwargs = {
        "MetricDataQueries": data_queries,
        "StartTime": start_dt,
        "EndTime": end_dt,
        "ScanBy": event.get("scan_by", "TimestampAscending"),
    }

    results, token, pages = {}, None, 0
    messages = []
    while True:
        if token:
            kwargs["NextToken"] = token
        resp = cw.get_metric_data(**kwargs)
        for r in resp.get("MetricDataResults", []):
            acc = results.setdefault(
                r["Id"],
                {"id": r["Id"], "label": r.get("Label"), "timestamps": [], "values": [],
                 "status": r.get("StatusCode")},
            )
            acc["timestamps"].extend(t.isoformat() for t in r.get("Timestamps", []))
            acc["values"].extend(r.get("Values", []))
            acc["status"] = r.get("StatusCode", acc["status"])
        messages.extend(resp.get("Messages", []))
        token = resp.get("NextToken")
        pages += 1
        if not token or pages >= 5:
            break

    out = []
    for r in results.values():
        vals = r["values"]
        r["datapoints"] = len(vals)
        if vals:
            r["summary"] = {
                "min": round(min(vals), 6),
                "max": round(max(vals), 6),
                "avg": round(sum(vals) / len(vals), 6),
                "latest": round(vals[-1], 6),
            }
        else:
            r["summary"] = None
            r["note"] = (
                "No datapoints. The metric may not exist for these dimensions, or the "
                "resource may not be instrumented (for Container Insights, the CloudWatch "
                "Observability add-on must be installed on that cluster)."
            )
        out.append(r)

    return {
        "start_time": start,
        "end_time": end,
        "results": out,
        "messages": messages,
        "truncated": bool(token),
    }
