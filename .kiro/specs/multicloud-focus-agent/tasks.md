# Tasks — Multicloud FinOps Agent (FOCUS)

`[ ]` not started · `[~]` in progress · `[x]` done

**Demo: Wednesday 2026-08-19.** Written Wednesday 2026-08-12 — 7 days.

Phase 1 ships a working demo on **CUR 2.0**, which already has 11 months of
history. FOCUS is switched on now purely so history accumulates; nothing in the
demo reads it. Accuracy hardening and `focus-mcp` are deliberately post-demo.

---

## Phase 0 — Start the clock (today, not demo-critical)

- [x] **T1. Create the FOCUS 1.0 Data Export.** ✅ **DONE 2026-08-12 06:13 UTC.**
      `focus-1-0` HEALTHY. Verified: table `FOCUS_1_0_AWS`, 48 columns,
      `s3://finops-focus-<account-id>-us-east-1/raw/provider=aws`, us-east-1,
      `PARQUET`/`PARQUET`/`OVERWRITE_REPORT`, `SYNCHRONOUS`.
      First delivery expected within ~24h (check 2026-08-13); `LastRefreshedAt` is
      null until then, which is normal.
      Bucket created with public access blocked, AES256 SSE, and a policy allowing
      only `bcm-data-exports.amazonaws.com` `s3:PutObject` plus a non-TLS deny.
      Rationale for urgency, now locked in: Data Exports does **not** backfill —
      the `cur` export created 2025-10-28 has no partition before
      `BILLING_PERIOD=2025-10`.

---

## Phase 1 — Demo on CUR 2.0 (by 2026-08-19)

### Data source — already exists, nothing to build

The demo queries the **existing `cur` export**:
`s3://amzn-s3-cur/cur/` — 11 partitions `BILLING_PERIOD=2025-10` → `2026-08`,
22 objects, 48.6 MB, CUR 2.0 hourly with resource-level detail.

- [x] **T2. Register the CUR table in Glue.** ✅ **DONE 2026-08-12.**
      Created `cur_database.cur2` via Athena DDL — 114 columns generated from
      `cur-Manifest.json` (72 string, 34 double, 4 timestamp, 4 `map<string,string>`:
      `cost_category`, `discount`, `product`, `resource_tags`).
      **Actual data location is `s3://amzn-s3-cur/cur/cur/data/`** — prefix `cur` plus
      export name `cur`, hence the doubled segment.
      Partition projection on `billing_period`, range `2025-10,NOW`, format `yyyy-MM`,
      `storage.location.template` mapping to the uppercase `BILLING_PERIOD=` path. No
      crawler, no `MSCK REPAIR`. Athena results → `s3://finops-focus-<account-id>-us-east-1/athena-results/`.
      _Verified:_ all 11 partitions readable, ~2.9M rows total (139K–394K/month).
      The pre-existing `cur_database.cid_cur2` was **not** used — it points at the
      single-partition CID path and carries no history.

- [x] **T3. Confirm Cost Explorer answers.** ✅ **DONE 2026-08-12.** 13 months returned.

### Accuracy baseline — established 2026-08-12

`sum(line_item_unblended_cost)` from `cur_database.cur2` reconciles **exactly** with
Cost Explorer `UnblendedCost` for all 11 months:

| Month | Athena | Cost Explorer |
|---|---|---|
| 2025-10 | 1,789.58 | 1,789.5807 |
| 2025-11 | 1,991.06 | 1,991.0631 |
| 2025-12 | 2,043.07 | 2,043.0729 |
| 2026-01 | 2,247.62 | 2,247.6229 |
| 2026-02 | 2,596.95 | 2,596.9464 |
| 2026-03 | 3,187.69 | 3,187.6856 |
| 2026-04 | 3,466.60 | 3,466.5973 |
| 2026-05 | 3,700.47 | 3,700.4675 |
| 2026-06 | 3,502.50 | 3,502.5029 |
| 2026-07 | 4,182.48 | 4,182.4847 |
| 2026-08 MTD | 1,744.47 | 1,744.4713 |

This is the reference for T16: the *data* is provably right, so any wrong answer in
the demo is the agent's tool/metric selection, not the source.

### Repo surgery

- [x] **T4. Remove the `aws-api-mcp` target.** ✅ **DONE 2026-08-12.**
      Deleted `module.agentcore_runtime`, `module.lambda_proxy`, both module dirs,
      `terraform/tool-schemas/aws_api_mcp.json`, `src/lambda/proxy/`,
      `mcp_server_image_*` and `runtime_aws_policy_arn` vars, two Makefile tflint lines,
      and the misleading README Marketplace prerequisite.
      **The gateway module hid three references** the root module didn't show:
      `iam.tf` granted `lambda:InvokeFunction` on the proxy ARN, `outputs.tf` exposed its
      `target_id`, `variables.tf` declared `lambda_function_arn`. `terraform validate`
      caught all three — a root-module grep would have missed them. Side benefit: the
      gateway role can now only invoke the two remaining MCP Lambdas.
      `terraform validate` → Success. `tflint` not installed, not run.

- [x] **T5. Remove `test-mcp`.** ✅ **DONE 2026-08-12.**
      Removed from `tool_schema_files` and `mcp_lambda_targets`, deleted the `mcp_test`
      module block, the `mcp_test_lambda_arn` output, the `mcp_client_config` entry,
      `terraform/tool-schemas/test.json`, `src/lambda/mcp_servers/test/`, and
      `test_test_mcp()` from `scripts/test_mcp_lambdas.py`.
      `terraform validate` → Success. `py_compile` → OK.
      **T4+T5 combined: 23 files, 29 insertions, 1,096 deletions.**

- [x] **T6. Keep `athena-mcp` as-is.** ✅ **VERIFIED NO-OP 2026-08-12.**
      Confirmed it hardcodes **no** database or table. It exposes a generic Athena
      surface — `start_query_execution`, `get_query_execution`, `get_query_results`,
      `list_query_executions`, `list_databases`, `list_tables`, `get_table_metadata`,
      `stop_query_execution` — so the model discovers `cur_database.cur2` at runtime and
      writes its own SQL. No code change needed.
      Its only config is `CUR_OUTPUT_LOCATION`, derived from
      `cur_athena_output_location` or `s3://${cur_bucket_name}/athena-results/`.
      `cross_account_enabled = false` already, which is what we want.
      ⚠️ Because the model authors raw SQL against a discovered schema, **accuracy rests
      entirely on prompt and schema guidance** — this is the hallucination surface T16
      addresses.

### Deploy — configure and apply

**⚠️ Config gotcha found during the T6 inspection.**
`athena-mcp`'s IAM scopes S3 to `arn:aws:s3:::${cur_bucket_name}/*` **and**
`arn:aws:s3:::*-athena-results/*`. The second matches a bucket whose *name* ends in
`-athena-results`, **not** a bucket with an `athena-results/` prefix. So
`finops-focus-<account-id>-us-east-1` matches neither pattern — pointing Athena output
there yields `AccessDenied` on `PutObject` after a deploy that otherwise looks healthy.

Therefore:

```hcl
cur_bucket_name            = "amzn-s3-cur"   # holds the 11-month CUR; grants read + write
cur_athena_output_location = ""              # defaults to s3://amzn-s3-cur/athena-results/
```

Leaving the output location empty is deliberate: the default lands inside
`cur_bucket_name`, which IAM already covers. Do **not** repoint it at the FOCUS bucket
without widening the policy first.

- [x] **T7. Configure for us-east-1.** ✅ **DONE 2026-08-12.**
      Created `terraform/config/.env` (`AWS_PROFILE=default`, `AWS_REGION=us-east-1`) and
      `terraform/config/terraform.tfvars`. Both **gitignored** — `.gitignore:46` and
      `.gitignore:17` — so the two non-obvious settings live only on this machine:
      `cur_bucket_name = "amzn-s3-cur"` with `cur_athena_output_location = ""` (see the
      IAM note above), and an explicit `cognito_domain_prefix`.
      **The domain prefix must NOT be customer-named**: the Cognito hosted domain is
      publicly resolvable DNS (`https://<prefix>.auth.<region>.amazoncognito.com`), so a
      customer name there would publish the association. Use a neutral name plus a random
      suffix for global uniqueness. (Actual value intentionally not recorded here.)
      _`terraform plan`: 21 add / 0 change / 0 destroy_ — all 21 enumerated, and the
      runtime/proxy/VPC/test exclusion check returned NONE. **This retroactively closed
      the outstanding plan criterion for T4 and T5.**
      Verified pre-apply: `gateway_cognito_token_url` contains no account ID and no
      customer name; `management_role_arn = ""`; `cross_account_enabled = false`.

- [x] **T8. Deploy.** ✅ **DONE 2026-08-12.** `apply` + `update-schemas` both clean.
      Gateway `READY`, protocol `MCP`, authorizer `CUSTOM_JWT` (the COGNITO wrapper
      resolves to CUSTOM_JWT as designed). Targets `athena-mcp` (8 tools) and
      `cost-explorer-mcp` (6 tools), both `READY`.
      ⚠️ **Live identifiers deliberately not recorded here — this repo is public.**
      Gateway id/endpoint, Cognito client id, discovery URL and token URL all come from
      `make output`; the client secret from `make show-cognito-creds`.

      **Two failures on the way — both worth remembering:**

      **1. Orphaned stack from 2026-03-30 blocked the first apply** with
      `EntityAlreadyExists` / `ResourceAlreadyExistsException`. `*.tfstate` is gitignored,
      so a fresh clone has no record of prior deployments — always
      `list-roles`/`list-functions`/`list-gateways` for the `project_name` prefix before a
      first apply. Deleted with approval: 5 gateway targets, gateway
      `finops-mcp-gateway-i67kcteidq`, runtime `finops_mcp_mcp_runtime-bJWqjO8Ix5`,
      5 Lambdas, 6 log groups, 7 IAM roles (inline policies deleted and managed policies
      detached first). That stack predated upstream `140b6af` — it still had
      `cur-analyst-mcp`.
      **Deliberately left alone:** everything `aiops-mcp-*` (separate stack) and the four
      `hosted_agent_*` runtimes with their Cognito pools (unrelated).

      **2. IAM propagation race on the gateway targets.** Second apply created 19/21 then
      failed both targets with `ValidationException: Gateway service is not authorized to
      perform AssumeRole on Gateway role`. The trust policy was **correct**
      (`bedrock-agentcore.amazonaws.com` + `sts:AssumeRole` + `SourceAccount`/`SourceArn`
      conditions) — the role was created at 06:53:01 UTC and `CreateGatewayTarget`
      validated it seconds later. A bare re-apply succeeded. **Do not "fix" the trust
      policy when this appears; just retry.**

### Deploy — verify

- [x] **T9. Capture outputs.** ✅ **DONE 2026-08-12.**
      Verified live: gateway `READY` / `MCP` / `CUSTOM_JWT`; both targets `READY` after the
      schema push; `management_role_arn = ""` and `cross_account_enabled = false`
      confirming single-account.
      Values are **not** written into this repo (it is public) — retrieve with
      `make output` and `make show-cognito-creds`. What QuickSuite needs at T12:
      `gateway_endpoint`, `gateway_cognito_client_id`, `gateway_cognito_client_secret`,
      `gateway_cognito_token_url`, `gateway_cognito_scope`.
      D10 confirmed in the live output: the token URL contains **no account ID and no
      customer name**.

### Auth and client

- [x] **T10. Cognito creds → token → JWT smoke test.** ✅ **DONE 2026-08-12.**
      `make get-token` → access token, 3600s. `make test-jwt` → **HTTP 200**, MCP
      `initialize` handshake returning `protocolVersion 2025-03-26`,
      `serverInfo finops-mcp-gateway v1.0.0`, capabilities `tools`/`prompts`/`resources`.
      Went further than the criterion and called `tools/list` directly: **14 tools**
      returned, namespaced per target — `athena-mcp___*` (8) and
      `cost-explorer-mcp___*` (6). `initialize` alone would not have proved the targets
      respond; this does.
      Token claims confirm **D9** exactly: `token_use: access`, `scope: finops-mcp/invoke`,
      no `aud`, no user identity — pure client_credentials M2M, no SSO anywhere.
      ⚠️ **`make get-token` echoes the raw JWT to stdout.** It is a live bearer token —
      never run it on a shared screen during the demo, and keep `.gateway-token.json`
      out of any recording. (It is gitignored.)
- [x] **T11. Test both Lambdas.** ✅ **DONE 2026-08-12.**
      `make test-lambdas` → all tests completed successfully. `cost-explorer-mcp` returned
      real `SERVICE` dimension values for 2026-07-13→2026-08-12; `athena-mcp` listed
      `cur_database` ("CUR 2.0 data for AWS FinOps Agent").

      **A T5 miss surfaced here.** The first run died with
      `NameError: name 'test_test_mcp' is not defined` — my T5 edit removed the function
      but not its entry in `for test_fn in [test_test_mcp, ...]`. My post-T5 verification
      grep used `mcp_test|test-mcp`, which matches **neither** the underscored
      `test_test_mcp`. Lesson: when removing a component, grep the identifier in *every*
      casing/separator form (`test-mcp`, `mcp_test`, `test_test_mcp`, `test_mcp`), not just
      the resource name. Fixed; `py_compile` OK.
      (`terraform/.terraform/modules/modules.json` still lists `mcp_test` — generated
      cache, gitignored, refreshes on `init`. Harmless.)

      **Went beyond the criterion — full end-to-end query through the gateway.**
      `list_databases` never writes to S3, so it does not exercise the IAM path flagged at
      T7. So a real query was run over the gateway with a Cognito JWT:
      `SELECT billing_period, round(sum(line_item_unblended_cost),2) FROM cur_database.cur2
      GROUP BY 1 ORDER BY 1` — via `athena-mcp___start_query_execution` →
      `get_query_execution` → `get_query_results`. Returned all 11 months, figures
      **identical to the Cost Explorer reconciliation table above**.
      Path proven: Cognito JWT → Gateway → Lambda → Athena → Glue → S3 → back. Only
      QuickSuite remains (T12).

      Worth noting: the `start_query_execution` tool schema **already documents** the
      output-location constraint — "defaults to the configured CUR bucket's
      `athena-results/` prefix, which is the only bucket guaranteed to be writable …
      Supplying a different bucket will fail with 'Unable to verify/create output
      bucket'". Upstream knew; the model is warned in-schema. Good sign for T16.
- [x] **T12. Create the Quick Suite agent.** ✅ **DONE 2026-08-14.**
      Connector `FinOps Gateway` created via **Connectors → Create for your team →
      Model Context Protocol**, Service-to-service OAuth, Public network. Status `Ready`,
      **14/14 tools** registered and namespaced (`athena-mcp___*`, `cost-explorer-mcp___*`).
      Validated with **Test action APIs** before building the agent, then end-to-end:
      the 3-step Athena chain (`start_query_execution` → `get_query_execution` →
      `get_query_results`) returned all 11 months matching the Cost Explorer
      reconciliation, and resource-level and Bedrock token-split queries both worked.
      ⚠️ **The shipped `quicksuite-agent-setup.md` is wrong in two ways** — it says
      *Integrations* (current UI is **Connectors**) and points at `quicksuite.ai`, framing
      it as a *"third-party service"*. Amazon Quick Suite is an AWS service
      (docs.aws.amazon.com/quick). Persona used: `docs/quicksuite-agent-persona.md`.

### Rightsizing capability — added 2026-08-14 after customer question

CelcomDigi's FinOps manager asked whether the demo covers EKS rightsizing at pod, node and
cluster level. Assessment against live data:

| Level | Available today | Gap |
|---|---|---|
| Cluster — idle clusters, efficiency | ✅ cost side (3 × $446.40/mo control plane, `test-old-cluster` surfaced) | utilization |
| Node — cost, pod→node rollup | ✅ via `split_line_item_parent_resource_id` | utilization, bin-packing |
| Pod — requests vs usage **cost impact** | ✅ EKS split cost allocation: 26,096 rows, $28.36 used vs **$111.99 unused** | utilization %, target request values |

**Blocker found:** split-cost data is **not** in the demo table. `cur` → `cur2`
(11 months) has `INCLUDE_SPLIT_COST_ALLOCATION_DATA: FALSE`; `cid-cur2` → `cid_cur2`
has it TRUE but only **one** partition (2026-08). Trend and pod-rightsizing cannot come
from the same table.

**Container Insights is already live** on `demo-cluster` (CloudWatch Observability add-on)
with `pod_cpu_request`, `pod_cpu_usage_total`, `pod_memory_request`,
`pod_memory_working_set` and the `*_reserved_capacity` variants. Proven computable via
`GetMetricData` **metric math** (`use/req*100`) — measured last 24h:
`demo-web` **0.06%**, `demo-api` **0.06%**, `coredns` 1.53%, `cloudwatch-agent` 4.10%
of requested CPU. Note `pod_cpu_utilization_over_pod_request` does **not** exist — only
`over_pod_limit` — so the ratio must be computed from the two raw metrics.
Only `demo-cluster` reports; the other five clusters are uninstrumented.

- [x] **T12A. Add `cid_cur2` to the persona.** ✅ **DONE 2026-08-14.**
      Live agent updated in the Quick Suite console; `docs/quicksuite-agent-persona.md`
      updated to match so the file stays the rebuild source of truth.
      Athena Configuration now describes **two** tables with explicit selection rules:
      `cur2` (default, 11 months, no `split_line_item_*` columns) and `cid_cur2`
      (pod/container questions only, **2026-08 alone** — the agent must state that
      limitation and never present a pod figure as a trend).
      Also captured: `split_line_item_split_usage_ratio` is typed **varchar** and must be
      cast before aggregation — `avg()` on it fails with `FUNCTION_NOT_FOUND`.
      ⚠️ If the console wording differs from the file, align the file — it is what a
      rebuild would be driven from.
- [x] **T12B. Build `cloudwatch-mcp` Lambda.** ✅ **DONE 2026-08-14.**
      `list_metrics` + `get_metric_data` (metric math). Reads the **CloudWatch Metrics
      API**, not Container Insights specifically; `ContainerInsights` is simply the first
      namespace targeted. IAM: `cloudwatch:ListMetrics`, `cloudwatch:GetMetricData`
      (neither supports resource scoping).
      **Not** the awslabs `cloudwatch-mcp-server`: it ships **stdio**, and Quick requires
      remote HTTP — *"Local stdio connections are not supported"*. Hosting it would
      reintroduce the container + AgentCore Runtime + proxy chain deleted in T4.

      **Deployed with `-target=module.mcp_cloudwatch`** — 6 added, 0 changed, 0 destroyed.
      Gateway and both existing targets deliberately out of scope; `athena-mcp` stayed at
      8 tools and `cost-explorer-mcp` at 6 throughout.

      **Tested directly via `aws lambda invoke`** with a synthetic
      `--client-context` (`{"custom":{"bedrockAgentCoreToolName":"cloudwatch-mcp___<tool>"}}`),
      bypassing the gateway entirely:
      - `list_metrics` → 200, 42 metrics, dimensions enumerated
      - `get_metric_data` simple → 200, 24 pts, `pod_cpu_request` = 50 millicores
      - `get_metric_data` **metric math** (`m1/m2*100`) → 200, `demo-web` at **0.059%**
        of requested CPU — matches the direct CLI measurement (0.0592 vs 0.0591), so the
        Lambda passes the expression through and CloudWatch computes it
      - uninstrumented cluster → 0 datapoints **plus** the "not instrumented" note
      - bad date, start≥end, invalid statistic, invalid query id, missing args, unknown
        tool → all clean `{"error": ...}` at HTTP 200, **no `FunctionError`**

      That last row matters for agent behaviour: a crash gives the model an opaque
      failure, a clean message lets it self-correct and retry.

      **Discovery:** `ContainerInsights` exposes **`FullPodName`** as well as `PodName`.
      `PodName` aggregates the Deployment; `FullPodName` is the individual replica
      (`demo-web-585498bbfd-gxmtz`). Use in T12D — "which workload" and "which replica"
      are different questions.
- [x] **T12C. Add as a third gateway target.** ✅ **DONE 2026-08-14.**
      Applied with **`-target`** isolation on the new target plus
      `aws_iam_role_policy.gateway_permissions` only — `1 added, 1 changed, 0 destroyed`.
      The two working targets were never in scope.
      **Isolation verified:** immediately after apply and *before* `update-schemas`,
      `athena-mcp` was still **8** tools and `cost-explorer-mcp` still **6**; only
      `cloudwatch-mcp` sat at the Terraform placeholder of 1. This is the concrete proof
      that `-target` avoids the D15 schema-stripping trap — a broad apply would have
      reverted 8→1 and 6→1.
      `make update-schemas` then reported **3/3 targets**, pushing `cloudwatch-mcp` 1→2
      and leaving the others unchanged.
      **Final: 16 tools** — athena-mcp 8, cost-explorer-mcp 6, cloudwatch-mcp 2, all
      `READY`. Confirmed end-to-end via `tools/list` through the gateway with a live
      Cognito JWT: `cloudwatch-mcp___get_metric_data`, `cloudwatch-mcp___list_metrics`.
      Revert point before this step: commit `d0f10a7`.

      ⚠️ **Sync does NOT activate new tools — the connector must be RECREATED.**
      After `update-schemas`, Quick Suite's Sync surfaced both cloudwatch tools in a
      read-only **Disabled** table with no toggle. Docs (mcp-integration.html,
      Limitations): *"Tool lists remain static after initial registration."*
      Rebuilt as connector `FinOps Gateway v2` on the same endpoint. See D17 for the
      safe order (create v2 → verify 16 → link to agent → unlink old → delete old).
      Cognito values for the rebuild: `make show-cognito-creds`.

- [x] **T12E. Grant `athena-mcp` read access to the `cid_cur2` bucket.**
      ✅ **DONE 2026-08-14.** Surfaced by the live agent: `cur2` queries succeeded but
      `cid_cur2` failed on S3 permissions. Cause: Athena reads S3 as the CALLER and
      `cid_cur2` lives in a different bucket from `cur_bucket_name`. T12A added the
      table to the persona without extending the Lambda policy.
      New var `additional_cur_bucket_names` (read-only, value in gitignored tfvars).
      Applied with `-target=module.mcp_athena.aws_iam_role_policy.lambda_permissions`
      → **0 added, 1 changed, 0 destroyed**; set-comparison of the inline policy
      before/after showed **0 permissions lost, 6 gained, no Deny**; gateway tool
      counts unchanged at 8/2/6. Verified: `cid_cur2` query SUCCEEDED,
      **$28.36 used / $111.99 unused**. Recorded as D18.
      Note: full-table row count for 2026-08 is **202,703**, not the 26,096 recorded
      earlier — the cost figures match exactly, so the earlier count was a narrower
      filter. Reconcile before quoting a row count publicly.

- [ ] **T12D. Update the persona** with routing for utilization questions and the
      measured-vs-inferred rule.

### Demo assets

- [ ] **T13. Architecture diagram — current + future.** One view showing today's CUR 2.0
      path, and the FOCUS + Azure target state. This is what carries the multicloud
      buy-in; it is a **deliverable**, not a nice-to-have.
- [ ] **T14. Demo script.** A short fixed question set that reliably works, ordered to
      tell a story: total trend → service breakdown → the Jun→Jul +19% jump → resource
      detail. Real material available: 12 months $1,420 → $4,182, EKS $5,155 /
      QuickSight $2,913 / Bedrock $1,038 across 12+ services and 3 regions.
- [ ] **T15. Leak check.** No Isengard account id in the Cognito domain, token URL, or
      anything on screen. Terminal and console off-screen or sanitised.

---

## Phase 1.5 — Post-demo hardening

- [ ] **T16. Accuracy pass using uno-tam's logic** as the reference model — routing
      rules, forced metric selection, anti-hallucination contract, verifiability gate.
      Deferred deliberately: the stock tool schema lets the model choose columns and
      metrics freely, which is where cost agents produce confidently wrong answers.
- [ ] **T17. Build `focus-mcp`** and the raw→focus transform once `focus-1-0` has
      history worth querying. D4's seam argument applies here, not to the demo.
- [ ] **T18. Investigate FOCUS backfill.** Determine whether AWS can deliver historical
      FOCUS periods (Azure can: 13 months via portal, 7 years via API). If not, CUR 2.0
      → FOCUS mapping over the existing 11 months is the alternative bridge.

---

## Phase 2 — Azure · 🚫 BLOCKED

**No Azure access of any kind.** Design-only. Do not build against invented data —
a mock validates the mock.

- [ ] **T19. UNBLOCK: obtain Azure FOCUS output** — a real or sanitised sample from the
      customer, or a tenant. Everything below waits on this.
- [ ] **T20.** Azure FOCUS export, version `1.0r2`, Parquet+Snappy, Overwrite ON, scoped
      at EA enrollment or MCA billing account (management group scope is unsupported).
- [ ] **T21.** Decide the Blob → S3 copy mechanism.
- [ ] **T22.** Decide Azure credentials for Lambda.
- [ ] **T23.** Resolve the deferred schema risks (design.md): Parquet numeric types,
      `Tags` shape, column-set intersection.
- [ ] **T24.** Extend the transform for Azure's layout. No change to `focus-mcp`.
- [ ] **T25.** Add `azure` to the projection enum. One-line DDL change.
- [ ] **T26.** Add the `azure-api-mcp` target.

---

## Week shape

| Day | Focus |
|---|---|
| Wed 08-12 | ✅ T1 FOCUS export · ✅ T2 Glue table + reconciliation · ✅ T4–T6 surgery |
| Thu 08-13 | T7–T9 (configure + deploy us-east-1); confirm FOCUS data landed |
| Fri 08-14 | T10–T12 (Cognito → QuickSuite end to end) |
| Mon 08-17 | T13 (architecture diagram) |
| Tue 08-18 | T14–T15 (script, leak check), dry run |
| Wed 08-19 | **Demo** |

Buffer is Mon–Tue. If deploy slips past Friday, T13 is the item to protect — the
diagram carries the multicloud pitch even if the live demo is thin.
