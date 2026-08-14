# Requirements — Deploy FinOps Agent to ap-southeast-5 (Malaysia), Non-VPC Mode

> **SUPERSEDED 2026-08-12** by `.kiro/specs/multicloud-focus-agent/`.
> Kept for the region-verification facts, which remain valid. Its D6 and T3
> (Marketplace container image, ap-southeast-5 ECR path) are **obsolete** — the
> `aws-api-mcp` target that required them has been dropped.

## Overview

This spec covers deploying the existing AWS FinOps Agent to the AWS
**Asia Pacific (Malaysia)** region, `ap-southeast-5`, using **non-VPC mode**
(`enable_vpc = false`).

The application code, Terraform, and the general deployment steps already exist
(see `README.md`, `docs/architecture.md`, `docs/configuration.md`). This spec
does **not** rebuild them. It only captures what is specific to running in
`ap-southeast-5` without a VPC, and turns it into small, ordered tasks.

## Goal

Get a working FinOps Agent in `ap-southeast-5` where:

- The AgentCore Gateway is reachable with a JWT (Cognito) token.
- All three MCP Lambda targets work (`cost-explorer-mcp`, `athena-mcp`, and the
  `aws-api-mcp` proxy to the AgentCore Runtime).
- No VPC, no PrivateLink, and no NAT Gateway are created.

## In Scope

- Configuration for `ap-southeast-5` (region, non-VPC, CUR, auth).
- Region-specific checks (Marketplace container image, Cost Explorer global
  endpoint, Bedrock model access).
- Deploy, smoke test, and validate.
- Recording the outputs and any region notes in the repo docs.

## Out of Scope

- VPC / PrivateLink mode. We already confirmed `ap-southeast-5` does not offer a
  Cost Explorer (`ce`) interface endpoint or an AgentCore runtime data-plane
  endpoint, so VPC mode needs extra work and a NAT Gateway. That is a separate
  effort.
- Changing application logic or the Terraform module design.
- QuickSuite internal setup beyond pasting in the connector values (the client
  side is documented in `docs/quicksuite-agent-setup.md`).

## Verified Facts (checked live against ap-southeast-5)

These were confirmed by calling AWS APIs in the region, not assumed:

- **Available:** Lambda, S3, STS, CloudWatch Logs, X-Ray, Glue, Athena, Cognito,
  EC2, Bedrock.
- **Bedrock AgentCore is available:** control plane responds, the runtime API
  works (an existing runtime was found in `READY` state), and the gateway
  endpoint exists.
- **Bedrock Claude models are present** (Sonnet / Haiku / Opus families) — used
  by the test suite as an LLM judge and by `suggest_aws_commands`.
- **Cost Explorer (`ce`) is a global service.** It has no regional endpoint in
  `ap-southeast-5`; calls route to the global endpoint. This is fine in non-VPC
  mode because the Lambda reaches the public AWS endpoint over the AWS backbone.

## Assumptions and Decisions

- **AUTH-1:** Auth mode is `COGNITO` (default). It auto-creates an OAuth client
  for service-to-service callers such as QuickSuite. No external IdP needed.
- **ACCT-1:** Single-account deployment by default (gateway and CUR data in the
  same account). Cross-account (payer) mode is optional and only needed for
  org-wide Cost Explorer from a data-collection account. See task T2.
- **NET-1:** `enable_vpc = false`. Lambdas run in the Lambda-managed network and
  reach AWS services over public service endpoints (TLS, over the AWS backbone).
  Nothing is made publicly reachable.
- **CUR-1:** Both Cost Explorer and CUR data come from the **same deploying AWS
  account** — your own account. `cost-explorer-mcp` reads that account's cost
  data via the global CE API, and `athena-mcp` queries that account's own CUR
  2.0 export through Athena/Glue. Both tool families answer from one consistent
  data source, so the agent can mix them freely without contradiction.

## Prerequisites

- AWS CLI profile that can deploy into the `ap-southeast-5` account.
- Terraform >= 1.5.0 and `uv` installed. `tflint` optional.
- A CUR 2.0 export already set up in your account, with an Athena/Glue table
  (bucket, database, and table names known). If you do not have one yet, create
  it before starting — a new export takes up to 24 hours to deliver its first
  data to S3.
- An active AWS Marketplace subscription to `aws-api-mcp-server` in the
  deployment account.

## Success Criteria

The deployment is done when all of these are true:

1. `make plan` shows **no VPC resources** (no `module.vpc`, no VPC endpoints).
2. `make deploy` finishes with no errors and `make output` prints a gateway
   endpoint whose ARN region is `ap-southeast-5`.
3. `make test-jwt` returns HTTP 200 from the gateway.
4. `make test-lambdas` passes for all three targets.
5. A `cost-explorer-mcp` tool call returns real cost data (proves the global
   Cost Explorer endpoint works from `ap-southeast-5`).
6. An `athena-mcp` tool call returns rows from the CUR table.
7. The final gateway endpoint, IDs, and any region notes are written to the repo
   docs.
