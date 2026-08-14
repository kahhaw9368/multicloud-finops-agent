# Design — Deploy FinOps Agent to ap-southeast-5 (Malaysia), Non-VPC Mode

## What this design changes

The architecture stays the same as `docs/architecture.md`. We only change
**configuration** to target `ap-southeast-5` and to turn the VPC off. No module
code or application code changes are planned. If a region check fails (see
Risks), we handle it as a small follow-up task, not a redesign.

## Deployment shape

```
MCP Client (QuickSuite) --JWT--> AgentCore Gateway (ap-southeast-5)
                                       |
                                       v
          cost-explorer-mcp Lambda  --> Cost Explorer (global endpoint)
          athena-mcp Lambda         --> Athena + Glue + S3 (ap-southeast-5)
          lambda-proxy Lambda       --> AgentCore Runtime (ap-southeast-5)
```

All Lambdas run in the Lambda-managed network (no customer VPC). They reach AWS
services over public service endpoints using TLS, staying on the AWS backbone.

## Key decisions

### D1 — Region
`aws_region = "ap-southeast-5"` in `terraform.tfvars`, and
`AWS_REGION=ap-southeast-5` in `.env`. Both must match.

### D2 — Non-VPC
`enable_vpc = false`. The shipped `terraform.tfvars.example` sets this to `true`,
so this is the single most important value to change. With it false, the whole
VPC module and every interface endpoint is skipped. This avoids the two
`ap-southeast-5` gaps we found (no `ce` endpoint, no runtime data-plane
endpoint).

### D3 — Auth
`gateway_auth_type = "COGNITO"`. The stack auto-provisions a Cognito user pool
and OAuth client. `cognito_domain_prefix` must be globally unique — leave empty
to auto-generate `<project_name>-<account_id>`.

### D4 — Account model
Single-account by default: leave `TF_VAR_management_account_profile` unset and
`management_account_profile = ""`. Cost Explorer still works because it is a
global API and returns data for the deploying account. Only switch to
cross-account if you need org-wide payer data from a data-collection account.

### D5 — Cost Explorer endpoint
No code change. The `cost_explorer` Lambda calls `get_aws_client("ce")` with no
region argument, so boto3 routes to the global Cost Explorer endpoint. We verify
this works at test time (success criterion #5) rather than assuming it.

### D6 — Marketplace container image
`mcp_server_image_registry` defaults to a **us-east-1** ECR path:
`709825985650.dkr.ecr.us-east-1.amazonaws.com/amazon-web-services/aws-api-mcp-server`.
The AgentCore Runtime in `ap-southeast-5` must be able to pull this image. There
are two possible outcomes, handled by task T3:

- If the Marketplace product publishes an `ap-southeast-5` ECR path, set
  `mcp_server_image_registry` to the `ap-southeast-5` equivalent.
- If a cross-region pull from us-east-1 is supported, keep the default.

This is the highest-uncertainty item and is checked early.

### D7 — Single data source: your own account
Both tool families read from the **deploying account only**:

- `cost-explorer-mcp` → global CE API → the deploying account's cost data.
- `athena-mcp` → Athena/Glue → the deploying account's own CUR 2.0 export.

Because both point at the same account, answers are internally consistent and
the agent can use either tool family for any question. CE is better for quick
aggregates, forecasts, and comparisons; CUR via Athena is better for
resource-level detail and custom SQL. No prompt restrictions or target gating
are needed.

```
                     ┌──► cost-explorer-mcp ──► CE API (global) ─┐
Gateway (ap-se-5) ───┤                                           ├──► same AWS account
                     └──► athena-mcp ──► Athena + Glue + S3 ─────┘
```

## Configuration values

### `terraform/config/.env` (single-account)

```bash
AWS_PROFILE=<your-ap-southeast-5-profile>
AWS_REGION=ap-southeast-5
```

### `terraform/config/terraform.tfvars`

```hcl
project_name = "finops-mcp"          # lowercase, starts with a letter
aws_region   = "ap-southeast-5"

gateway_auth_type = "COGNITO"

# CUR (match your real export)
cur_bucket_name            = "<your-cur-bucket>"
cur_athena_output_location = ""       # defaults to s3://<bucket>/athena-results/

# Non-VPC — the important one
enable_vpc = false

# Marketplace image — confirm registry/version in T3
mcp_server_image_version = "1.2.0"
# mcp_server_image_registry = "709825985650.dkr.ecr.ap-southeast-5.amazonaws.com/amazon-web-services/aws-api-mcp-server"

environment = "dev"
tags = {
  Project    = "AWS FinOps Agent"
  ManagedBy  = "Terraform"
  Owner      = "<your-alias>"
  CostCenter = "<your-cost-center>"
}
```

## What we are NOT changing

- No edits to `terraform/modules/*`.
- No edits to Lambda source under `src/`.
- No VPC, no NAT Gateway, no interface endpoints.

## Risks and mitigations

| ID | Risk | Likelihood | Mitigation / Task |
|----|------|-----------|-------------------|
| R1 | Marketplace image not pullable in `ap-southeast-5` | Medium | T3 checks the registry/version before deploy; fall back to `ap-southeast-5` ECR path or confirm cross-region pull |
| R2 | CUR Athena table only shows one billing period | Medium | T5 runs the `SELECT DISTINCT billing_period` check and fixes the table location if needed |
| R3 | `cognito_domain_prefix` collision (must be globally unique) | Low | Leave empty to auto-generate from account id |
| R4 | Cost Explorer global endpoint call fails from region | Low | T11 validates a real cost query (success criterion #5) |
| R5 | Marketplace subscription missing in the deploy account | Medium | T2 confirms subscription before deploy |
| R6 | Someone leaves `enable_vpc = true` from the example file | Medium | T7 sets it false; T8 `make plan` must show zero VPC resources |
| R7 | CUR export exists but has not delivered data yet (new exports take up to 24h) | Medium | T5 confirms rows are queryable before deploy; create the export ahead of time |

## Rollback

Non-VPC mode creates no stateful data resources of its own. `make destroy`
removes everything this stack created. The CUR bucket and Glue table are
pre-existing and are not managed or deleted by this stack.
