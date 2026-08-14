# Tasks — Deploy FinOps Agent to ap-southeast-5 (Malaysia), Non-VPC Mode

Small, ordered steps. Do them top to bottom. Each task lists what to do, how to
do it, and how to know it is done. Check the box when the "Done when" is true.

Legend: `[ ]` not started, `[~]` in progress, `[x]` done.

---

## Phase 1 — Pre-checks

### [ ] T1. Confirm AWS access to the ap-southeast-5 account
- **What:** Make sure your CLI profile can reach the target account and region.
- **How:**
  ```bash
  aws sts get-caller-identity --profile <your-profile>
  aws ec2 describe-regions --region ap-southeast-5 --query 'Regions[0].RegionName' --output text
  ```
- **Done when:** The identity is the account you want, and the region command
  prints `ap-southeast-5`.
- _Covers: prerequisites._

### [ ] T2. Confirm the AWS Marketplace subscription
- **What:** Confirm the deploy account is subscribed to `aws-api-mcp-server`.
- **How:** Open the [Marketplace listing](https://aws.amazon.com/marketplace/pp/prodview-lqqkwbcraxsgw)
  while signed into the deploy account and check it shows as subscribed.
- **Done when:** The subscription is active in the deploy account.
- _Covers: R5._

### [ ] T3. Confirm the container image registry for ap-southeast-5
- **What:** Decide the correct `mcp_server_image_registry` and
  `mcp_server_image_version` for this region. This is the riskiest item — do it
  before deploy.
- **How:** Check the Marketplace listing for the ap-southeast-5 ECR path. If it
  exists, plan to use:
  `709825985650.dkr.ecr.ap-southeast-5.amazonaws.com/amazon-web-services/aws-api-mcp-server`.
  If only us-east-1 is offered, note whether cross-region pull is allowed.
- **Done when:** You have written down the registry value and version you will
  put in `terraform.tfvars` (either the ap-southeast-5 path or the us-east-1
  default).
- _Covers: D6, R1._

### [ ] T4. Confirm tools are installed
- **What:** Terraform >= 1.5.0 and `uv` are present. `tflint` optional.
- **How:**
  ```bash
  terraform version
  uv --version
  ```
- **Done when:** Both commands print a version.

### [ ] T5. Verify your CUR Athena table is queryable and covers all billing periods
- **What:** Confirm your own account's CUR 2.0 export has delivered data and the
  Glue table points at the parent `data/` path, not a single month.
- **How:** In Athena (ap-southeast-5), run:
  ```sql
  SELECT DISTINCT billing_period FROM <db>.<table> ORDER BY billing_period;
  ```
  If only one month shows, fix the table location:
  ```sql
  ALTER TABLE <db>.<table> SET LOCATION 's3://<cur-bucket>/.../data/';
  ```
  If the query returns nothing at all, the export has not delivered yet — new
  CUR exports take up to 24 hours for the first drop.
- **Done when:** At least one billing period returns rows. Record the bucket,
  database, and table names for use in T8.
- _Covers: R2, R7._

---

## Phase 2 — Configuration

### [ ] T6. Create the config files
- **What:** Create `terraform/config/.env` and `terraform/config/terraform.tfvars`.
- **How:** Either run `make setup` (interactive wizard, validates against AWS)
  or `make setup-quick` (copies the example files to edit by hand).
- **Done when:** Both files exist under `terraform/config/`.

### [ ] T7. Set the region and turn VPC off
- **What:** Point the stack at ap-southeast-5 and disable VPC mode.
- **How:** Edit `terraform/config/.env`:
  ```bash
  AWS_PROFILE=<your-profile>
  AWS_REGION=ap-southeast-5
  ```
  Edit `terraform/config/terraform.tfvars`:
  ```hcl
  aws_region = "ap-southeast-5"
  enable_vpc = false
  ```
- **Done when:** `.env` region and `tfvars` region both say `ap-southeast-5`,
  and `enable_vpc = false`.
- _Covers: D1, D2, NET-1, R6._

### [ ] T8. Set CUR, auth, and image values
- **What:** Fill in the remaining required values.
- **How:** In `terraform.tfvars` set:
  ```hcl
  project_name             = "finops-mcp"
  gateway_auth_type        = "COGNITO"
  cur_bucket_name          = "<your-cur-bucket>"
  mcp_server_image_version = "1.2.0"
  # If T3 said so, also set:
  # mcp_server_image_registry = "709825985650.dkr.ecr.ap-southeast-5.amazonaws.com/amazon-web-services/aws-api-mcp-server"
  ```
- **Done when:** CUR bucket is your real bucket, auth is `COGNITO`, and the
  image registry/version match what T3 decided.
- _Covers: D3, D6._

### [ ] T9. Confirm single-account mode
- **What:** Make sure cross-account is off unless you truly need payer data.
- **How:** In `.env`, leave `TF_VAR_management_account_profile` unset. In
  `tfvars`, leave `management_account_profile = ""` (or absent).
- **Done when:** No management-account profile is set.
- _Covers: D4, ACCT-1._

---

## Phase 3 — Deploy

### [ ] T10. Initialize Terraform
- **How:** `make init`
- **Done when:** Terraform init succeeds with no errors.

### [ ] T11. Review the plan — check for zero VPC resources
- **What:** Make sure the plan is non-VPC and targets the right region.
- **How:** `make plan`
- **Done when:** The plan shows **no** `module.vpc`, no `aws_vpc_endpoint`, and
  no subnets. Resource ARNs/regions reference `ap-southeast-5`.
- _Covers: success criterion #1, R6._

### [ ] T12. Deploy
- **What:** Apply and push the tool schemas to the gateway.
- **How:** `make deploy`  (runs `apply-auto` + `update-schemas`)
- **Done when:** Apply finishes with no errors and schemas update without error.
- _Covers: success criterion #2._

### [ ] T13. Capture outputs
- **How:** `make output`
- **Done when:** You have the gateway endpoint and gateway id recorded, and the
  endpoint region is `ap-southeast-5`.
- _Covers: success criterion #2._

---

## Phase 4 — Auth and smoke test

### [ ] T14. Get Cognito credentials
- **How:** `make show-cognito-creds`
- **Done when:** You have `client_id`, `client_secret`, `token_url`, `scope`,
  and `discovery_url` saved for QuickSuite setup.
- _Covers: D3._

### [ ] T15. Fetch a token
- **How:** `make get-token`
- **Done when:** A token is written to `.gateway-token.json` with no error.

### [ ] T16. End-to-end JWT smoke test
- **How:** `make test-jwt`
- **Done when:** The gateway returns HTTP 200.
- _Covers: success criterion #3._

---

## Phase 5 — Validation

### [ ] T17. Test all MCP Lambdas
- **How:** `make test-lambdas`
- **Done when:** All three targets (`cost-explorer-mcp`, `athena-mcp`,
  `aws-api-mcp`) respond without error.
- _Covers: success criterion #4._

### [ ] T18. Validate Cost Explorer from ap-southeast-5
- **What:** Prove the global Cost Explorer endpoint works from this region.
- **How:** Run a cost query through the gateway, e.g.:
  ```bash
  make test-evals PYTEST_ARGS="-k cost"
  ```
  or call `get_cost_and_usage` via your MCP client.
- **Done when:** Real cost figures come back.
- _Covers: success criterion #5, D5, R4._

### [ ] T19. Validate Athena against the CUR table
- **What:** Prove Athena + Glue + S3 work in-region.
- **How:** Run an Athena tool call (`list_tables` then a small
  `start_query_execution` / `get_query_results`) via the client, or:
  ```bash
  make test-ground-truth PYTEST_ARGS="-k athena"
  ```
- **Done when:** Rows come back from the CUR table.
- _Covers: success criterion #6._

### [ ] T20. Configure the QuickSuite client (optional)
- **What:** Paste the Cognito values into QuickSuite's MCP connector.
- **How:** Follow `docs/quicksuite-agent-setup.md` using the values from T14 and
  the endpoint from T13.
- **Done when:** QuickSuite connects and lists the tools.

---

## Phase 6 — Document

### [ ] T21. Record the deployment result
- **What:** Save the region-specific outcome for future reference.
- **How:** Add a short note to the repo docs (for example a new
  `docs/deployment-ap-southeast-5.md`) with: gateway endpoint, gateway id,
  region, auth mode, the image registry value that worked (T3), and any CUR
  table fix from T5.
- **Done when:** The note is committed and links back to this spec.
- _Covers: success criterion #7._

---

## Traceability

| Success criterion (requirements.md) | Task(s) |
|-------------------------------------|---------|
| #1 No VPC resources in plan         | T7, T11 |
| #2 Deploy + endpoint in region      | T12, T13 |
| #3 JWT returns 200                  | T16 |
| #4 All Lambdas pass                 | T17 |
| #5 Cost Explorer returns data       | T18 |
| #6 Athena returns rows              | T5, T19 |
| #7 Outputs + notes recorded         | T21 |
