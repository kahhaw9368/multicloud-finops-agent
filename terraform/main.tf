# -----------------------------------------------------------------------------
# AIOps MCP Gateway Proxy - Main Configuration
# -----------------------------------------------------------------------------
# This Terraform configuration deploys:
# 1. MCP Lambda Servers - test, cost_explorer, athena
# 2. AgentCore Gateway - Exposes MCP endpoint for external clients
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

locals {
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
  })

  # Gateway ARN pattern for Lambda permissions
  gateway_arn_pattern = "arn:aws:bedrock-agentcore:${var.aws_region}:${data.aws_caller_identity.current.account_id}:gateway/*"

  # Tool schemas loaded from JSON files.
  # Single source of truth for (target name -> schema filename). Add a target
  # here and the gateway registration + `gateway_target_schemas` output stay
  # in sync.
  tool_schema_files = {
    "cost-explorer-mcp" = "cost_explorer.json"
    "athena-mcp"        = "athena.json"
    "cloudwatch-mcp"    = "cloudwatch.json"
  }
  mcp_tool_schemas = {
    for name, file in local.tool_schema_files :
    name => jsondecode(file("${path.module}/tool-schemas/${file}"))
  }
}

# mcp_lambda_targets is a separate locals block because it references
# module.mcp_* outputs (which can't be evaluated until those modules are
# resolved). Declared once here so both the gateway module call and the
# gateway_target_schemas output consume the same list — no drift.
locals {
  mcp_lambda_targets = [
    {
      name         = "cost-explorer-mcp"
      description  = "AWS Cost Explorer MCP tools"
      lambda_arn   = module.mcp_cost_explorer.function_arn
      tool_schemas = local.mcp_tool_schemas["cost-explorer-mcp"]
    },
    {
      name         = "athena-mcp"
      description  = "AWS Athena MCP tools"
      lambda_arn   = module.mcp_athena.function_arn
      tool_schemas = local.mcp_tool_schemas["athena-mcp"]
    },
    {
      name         = "cloudwatch-mcp"
      description  = "CloudWatch metrics MCP tools (utilization, rightsizing signals)"
      lambda_arn   = module.mcp_cloudwatch.function_arn
      tool_schemas = local.mcp_tool_schemas["cloudwatch-mcp"]
    },
  ]
}

# -----------------------------------------------------------------------------
# VPC for Lambda Functions (conditional)
# -----------------------------------------------------------------------------
module "vpc" {
  count  = var.enable_vpc ? 1 : 0
  source = "./modules/vpc"

  project_name = var.project_name
  aws_region   = var.aws_region
  vpc_cidr     = var.vpc_cidr

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Module 1: MCP Lambda Servers
# -----------------------------------------------------------------------------

# Cost Explorer MCP Lambda - AWS cost analysis tools
module "mcp_cost_explorer" {
  source = "./modules/mcp-lambda"

  project_name        = var.project_name
  server_name         = "cost-explorer"
  description         = "AWS Cost Explorer MCP tools for analyzing cloud costs"
  source_file         = "${path.module}/../src/lambda/mcp_servers/cost_explorer/lambda_function.py"
  aws_region          = var.aws_region
  timeout             = 30
  memory_size         = 128
  gateway_arn_pattern = local.gateway_arn_pattern

  # Cross-account configuration (uses locals from management-account-role.tf)
  cross_account_enabled     = local.cross_account_enabled
  cross_account_role_arn    = local.management_role_arn
  cross_account_external_id = local.cross_account_external_id

  iam_policy_statements = [
    {
      actions = [
        "ce:GetCostAndUsage",
        "ce:GetDimensionValues",
        "ce:GetTags",
        "ce:GetCostForecast"
      ]
      resources = ["*"]
    }
  ]

  # Security
  subnet_ids                     = var.enable_vpc ? module.vpc[0].private_subnet_ids : []
  security_group_ids             = var.enable_vpc ? [module.vpc[0].lambda_security_group_id] : []
  reserved_concurrent_executions = var.lambda_reserved_concurrent_executions
  log_retention_in_days          = var.log_retention_in_days
  lambda_kms_key_arn             = var.lambda_kms_key_arn

  tags = local.common_tags
}

# Athena MCP Lambda - Data lake query tools
module "mcp_athena" {
  source = "./modules/mcp-lambda"

  project_name        = var.project_name
  server_name         = "athena"
  description         = "AWS Athena MCP tools for querying data lakes"
  source_file         = "${path.module}/../src/lambda/mcp_servers/athena/lambda_function.py"
  aws_region          = var.aws_region
  timeout             = 60
  memory_size         = 256
  gateway_arn_pattern = local.gateway_arn_pattern

  # Cross-account intentionally OFF for athena-mcp. Under the CID topology,
  # CUR Parquet is S3-replicated from the payer into the data_collection account,
  # and the Glue catalog (cid_data_export) lives in data_collection too — so
  # Athena queries run against the Lambda's own execution role locally. The
  # management-account cross-account role is reserved for cost-explorer-mcp,
  # which needs org-wide CE data that only the payer can return.
  cross_account_enabled     = false
  cross_account_role_arn    = ""
  cross_account_external_id = ""

  # Default S3 output location for Athena queries. Callers that omit
  # output_location (e.g. QuickSuite) will have their query results written
  # here — which must be a bucket the cross-account role can write to.
  environment_variables = {
    CUR_OUTPUT_LOCATION = var.cur_athena_output_location != "" ? var.cur_athena_output_location : "s3://${var.cur_bucket_name}/athena-results/"
  }

  iam_policy_statements = concat([
    {
      actions = [
        "athena:StartQueryExecution",
        "athena:GetQueryExecution",
        "athena:GetQueryResults",
        "athena:ListQueryExecutions",
        "athena:StopQueryExecution",
        "athena:BatchGetQueryExecution",
        "athena:ListDatabases",
        "athena:ListTableMetadata",
        "athena:GetTableMetadata",
        "athena:GetDatabase",
        "athena:ListDataCatalogs",
        "athena:GetDataCatalog"
      ]
      resources = ["*"]
    },
    {
      actions = [
        "s3:GetBucketLocation",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:PutObject",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts"
      ]
      resources = [
        "arn:aws:s3:::${var.cur_bucket_name}",
        "arn:aws:s3:::${var.cur_bucket_name}/*",
        "arn:aws:s3:::*-athena-results",
        "arn:aws:s3:::*-athena-results/*"
      ]
    },
    {
      actions = [
        "glue:GetDatabase",
        "glue:GetDatabases",
        "glue:GetTable",
        "glue:GetTables",
        "glue:GetPartition",
        "glue:GetPartitions"
      ]
      resources = ["*"]
    }
    ],
    # Read-only access to any additional export buckets (e.g. a CID/split-cost
    # export in its own bucket). Athena reads S3 as the caller, so a Glue table
    # outside cur_bucket_name fails with an S3 permission error without this.
    length(var.additional_cur_bucket_names) > 0 ? [
      {
        actions = [
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        resources = flatten([
          for b in var.additional_cur_bucket_names : [
            "arn:aws:s3:::${b}",
            "arn:aws:s3:::${b}/*"
          ]
        ])
      }
  ] : [])

  # Security
  subnet_ids                     = var.enable_vpc ? module.vpc[0].private_subnet_ids : []
  security_group_ids             = var.enable_vpc ? [module.vpc[0].lambda_security_group_id] : []
  reserved_concurrent_executions = var.lambda_reserved_concurrent_executions
  log_retention_in_days          = var.log_retention_in_days
  lambda_kms_key_arn             = var.lambda_kms_key_arn

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Cognito Gateway Auth (conditional — only when gateway_auth_type = COGNITO)
# -----------------------------------------------------------------------------
locals {
  cognito_domain_prefix_effective = var.cognito_domain_prefix != "" ? var.cognito_domain_prefix : "${var.project_name}-${data.aws_caller_identity.current.account_id}"
}

module "cognito_gateway_auth" {
  count  = var.gateway_auth_type == "COGNITO" ? 1 : 0
  source = "./modules/cognito-gateway-auth"

  project_name  = var.project_name
  aws_region    = var.aws_region
  domain_prefix = local.cognito_domain_prefix_effective
  scope_name    = var.cognito_scope_name
  tags          = local.common_tags
}

# -----------------------------------------------------------------------------
# Module 4: AgentCore Gateway
# CloudWatch Metrics MCP Lambda - utilization and rightsizing signals.
# Reads the CloudWatch Metrics API; ContainerInsights is simply the first namespace
# targeted. Metric math (GetMetricData Expression) computes usage-vs-request ratios
# server-side, because Container Insights exposes no *_over_pod_request metric.
module "mcp_cloudwatch" {
  source = "./modules/mcp-lambda"

  project_name        = var.project_name
  server_name         = "cloudwatch"
  description         = "CloudWatch metrics MCP tools for utilization and rightsizing analysis"
  source_file         = "${path.module}/../src/lambda/mcp_servers/cloudwatch/lambda_function.py"
  aws_region          = var.aws_region
  timeout             = 60
  memory_size         = 256
  gateway_arn_pattern = local.gateway_arn_pattern

  # Metrics live in the deploying account alongside the clusters.
  cross_account_enabled     = false
  cross_account_role_arn    = ""
  cross_account_external_id = ""

  # Neither ListMetrics nor GetMetricData supports resource-level scoping.
  iam_policy_statements = [
    {
      actions = [
        "cloudwatch:ListMetrics",
        "cloudwatch:GetMetricData"
      ]
      resources = ["*"]
    }
  ]

  # Security
  subnet_ids                     = var.enable_vpc ? module.vpc[0].private_subnet_ids : []
  security_group_ids             = var.enable_vpc ? [module.vpc[0].lambda_security_group_id] : []
  reserved_concurrent_executions = var.lambda_reserved_concurrent_executions
  log_retention_in_days          = var.log_retention_in_days
  lambda_kms_key_arn             = var.lambda_kms_key_arn

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
module "agentcore_gateway" {
  source = "./modules/agentcore-gateway"

  project_name = var.project_name
  # Gateway only knows CUSTOM_JWT / AWS_IAM / NONE — COGNITO is a wrapper that
  # auto-provisions a Cognito IdP and then routes through the CUSTOM_JWT path.
  auth_type = var.gateway_auth_type == "COGNITO" ? "CUSTOM_JWT" : var.gateway_auth_type

  # JWT config: when COGNITO, auto-populated from the Cognito module.
  # When CUSTOM_JWT, uses user-supplied vars.
  # Cognito M2M tokens have no `aud` claim — we enforce auth via allowed_clients + allowed_scopes.
  jwt_discovery_url     = var.gateway_auth_type == "COGNITO" ? module.cognito_gateway_auth[0].discovery_url : var.jwt_discovery_url
  jwt_allowed_audiences = var.gateway_auth_type == "COGNITO" ? [] : var.jwt_allowed_audiences
  jwt_allowed_clients   = var.gateway_auth_type == "COGNITO" ? [module.cognito_gateway_auth[0].client_id] : var.jwt_allowed_clients
  jwt_allowed_scopes    = var.gateway_auth_type == "COGNITO" ? [module.cognito_gateway_auth[0].scope] : []

  # MCP Lambda targets — declared in `locals` above, shared with gateway_target_schemas output.
  mcp_lambda_targets = local.mcp_lambda_targets

  tags = local.common_tags

  depends_on = [
    module.cognito_gateway_auth,
    module.mcp_cost_explorer,
    module.mcp_athena,
    module.mcp_cloudwatch,
  ]
}
