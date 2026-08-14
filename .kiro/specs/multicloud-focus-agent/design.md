# Design — Multicloud FinOps Agent (FOCUS)

## Gateway targets

| Target | Change | Role |
|---|---|---|
| `focus-mcp` | **new**, replaces `athena-mcp` | Provider-agnostic SQL over the FOCUS table. Serves AWS and Azure identically. |
| `cost-explorer-mcp` | keep, narrowed | AWS-only: forecasts, RI/SP coverage & utilization, recommendations — things a FOCUS table does not carry. |
| `azure-api-mcp` | **new**, phase 2 | Azure resource metadata (Resource Graph / ARM). |
| `aws-api-mcp` | **drop** | Removes the Marketplace subscription, the ECR image path, `module.agentcore_runtime` and `module.lambda_proxy`. |
| `test-mcp` | **drop** | hello/echo. |

Named for the schema it speaks, not the engine it runs on — Athena is an
implementation detail, FOCUS is the contract. That naming is what keeps the tool
unchanged when Azure arrives.

## S3 layout

```
s3://<acct>-finops-focus-<region>/
├── raw/                                   ← verbatim provider output, never queried
│   ├── provider=aws/
│   │   └── focus-1-0/                     ← Data Exports <export-name>
│   │       ├── data/BILLING_PERIOD=2026-07/*.snappy.parquet
│   │       └── metadata/BILLING_PERIOD=2026-07/focus-1-0-Manifest.json
│   └── provider=azure/                    ← phase 2, copied from Blob
│       └── focus-1-0r2/
│           └── 20260701-20260731/<RunID>/{manifest.json,part_*.parquet}
│
├── focus/                                 ← the query surface: one Glue table
│   ├── provider=aws/billing_period=2026-07/*.snappy.parquet
│   └── provider=azure/billing_period=2026-07/*.snappy.parquet
│
└── athena-results/
```

Set Data Exports `S3Prefix = raw/provider=aws` and export name `focus-1-0`, and
the AWS raw path lands correctly with no work.

## Why raw/ and focus/ are separate

1. **The `x_` column sets don't match.** AWS FOCUS 1.0 ships 43 spec columns + 5
   AWS-specific; Azure ships 44 spec + ~50 `x_`. A union is only well-defined
   against the FOCUS core, so `focus/` holds exactly that, plus one
   `x_payload` JSON column preserving provider extras.
2. **Replay.** Moving to FOCUS 1.2 re-runs the transform over `raw/` instead of
   re-exporting 13 months from two providers.
3. **Azure has to be flattened anyway** — its date-range folder and RunID GUID
   are not Athena-addressable.

## Decisions

| ID | Decision |
|---|---|
| D1 | FOCUS 1.0 on both providers. Azure pinned `1.0r2`. |
| D2 | `provider` is a partition key from phase 1, with one value. This is the seam. |
| D3 | Curated partition keys are lowercase (`billing_period=`) even though AWS emits `BILLING_PERIOD=`. Consistency across providers beats matching one provider. |
| D4 | Keep the raw→focus transform when `focus-mcp` is built. **Deferred past the demo** (2026-08-12): the demo reads CUR 2.0, so nothing consumes the curated zone yet. The seam argument stands for phase 1.5 — querying `raw/` directly is still the shortcut that forces a rewrite. |
| D5 | Partition projection, no crawler. New months queryable the moment files land. |
| D6 | **Write by replacement, never append.** Delete-then-write the whole partition prefix each run. |
| D7 | **Read the manifest, never glob.** It is also the completeness signal — AWS delivers it only after all data files land. |
| D8 | Parquet on both sides. AWS Data Exports takes `Format: PARQUET` + **`Compression: PARQUET`** — there is no `SNAPPY` value on that API. Confirmed on this account's existing *CUR* exports; `S3OutputConfigurations` is part of `DestinationConfigurations` and so is table-independent, which is why it carries to a FOCUS export. Azure takes Parquet + Snappy. |
| D9 | `gateway_auth_type = "COGNITO"`, client_credentials M2M. No SSO — Identity Center publishes no OIDC discovery document. |
| D10 | `cognito_domain_prefix` set **explicitly**. Left empty it becomes `<project_name>-<account_id>`, which puts the account ID in the token URL shown in QuickSuite's connector UI. |
| D11 | `enable_vpc = false`. Region **us-east-1** (changed from ap-southeast-5 on 2026-08-12). apse5 was a presentation nicety with no customer-visible effect; us-east-1 already holds 79% of the spend, the CUR bucket, `cur_database`, the Athena `primary` workgroup and QuickSight. Deploying where everything already lives removes cross-region Athena, an unproven AgentCore deploy and a fresh Cognito pool from a 7-day critical path. apse5 remains the eventual customer-deployment region. |
| D12 | Single-account. Cross-account is the customer's deployment concern. |
| D13 | **Demo reads CUR 2.0, not FOCUS** (2026-08-12). The `cur` export at `s3://amzn-s3-cur/cur/` has 11 months (`2025-10`→`2026-08`); a FOCUS export created today would have one, because Data Exports does not backfill. So `athena-mcp` stays stock and un-renamed for the demo — calling it `focus-mcp` would lie about what it reads. FOCUS is switched on now solely to accumulate history. |
| D14 | **QuickSight/Quick account name `pos-malaysia` is IMMUTABLE — accepted as-is** (2026-08-12). One QuickSight account per AWS account, so a new Quick Suite agent does not rename it. `UpdateAccountSettings` accepts only `AwsAccountId`, `DefaultNamespace`, `NotificationEmail` and `TerminationProtectionEnabled` — there is **no** `AccountName` parameter, verified across the .NET v4 and PHP API references. `DescribeAccountSettings` returns the name but nothing writes it back; it is fixed at `CreateAccountSubscription`. The only change path is unsubscribe + re-subscribe, which **deletes assets and users in that Region** — unacceptable this close to the demo. Whether the name renders anywhere a demo audience sees is **unverified**; it was found via API, not in the UI. Mitigations if it surfaces: demo from the agent view only, give the *agent* a neutral name, frame the browser window. |
| D15 | **Always `make deploy`, never bare `make apply-auto`.** Terraform declares one placeholder tool per gateway target; `scripts/update_tool_schemas.py` pushes the real schemas post-apply. State therefore holds the placeholder, so **every** plan shows `target_configuration` updates that would strip schemas back to 1 tool per target (verified 2026-08-14: athena-mcp 8→1, cost-explorer-mcp 6→1; Lambda ARNs unaffected). `deploy` chains `apply-auto` + `update-schemas`, which restores them. Applying and stopping leaves a gateway that looks broken for reasons unrelated to the change. |
| D16 | **`cloudwatch-mcp` is a third Lambda target on the same gateway**, not a separate deployment — one Quick connector, one Cognito pool, one auth path, same module pattern. Reads the **CloudWatch Metrics API**; `ContainerInsights` is just the first namespace targeted, so the same tools serve `AWS/EC2`, `AWS/RDS` etc. Deliberately **not** the awslabs `cloudwatch-mcp-server`: it ships stdio transport, Quick supports remote HTTP only, and hosting it would reintroduce the container + AgentCore Runtime + proxy chain deleted in T4. Metric math (`GetMetricData` `Expression`) computes usage-vs-request server-side because Container Insights has no `*_over_pod_request` metric — only `*_over_pod_limit`. |
| D17 | **Quick Suite connector tool lists are immutable after registration.** Discovery runs once, at creation; the docs state *"Tool lists remain static after initial registration. To pick up server-side tool changes, you must delete the integration and recreate it."* Verified 2026-08-14: after `update-schemas` took the gateway to 16 tools, **Sync** surfaced the two `cloudwatch-mcp` tools in a **read-only Disabled table with no toggle** — the earlier "click Sync" advice was wrong. Consequence: adding a gateway target is a **two-part** change — Terraform + `update-schemas` on the AWS side, then a connector rebuild plus re-linking actions on the agent. Safe order: create a v2 connector on the same endpoint → confirm the full tool count → link it to the agent → unlink the old → only then delete the old. Never delete first; the agent drops to ACTIONS (0) and cannot launch. Precondition verified before rebuilding: all 16 tool schemas use JSON Schema Draft 7 (`required` as a root-level array), so the documented `Creation failed` publish trap does not apply. |
| D18 | **Every Athena table's S3 bucket must be in the `athena-mcp` Lambda's IAM policy.** Athena reads S3 with the **caller's** identity, so a Glue table outside `cur_bucket_name` resolves, returns metadata and accepts a query — then fails at execution with an S3 permission error, which reads like a table problem rather than an IAM one. Hit 2026-08-14 when T12A added `cid_cur2` to the persona: `cur2` lives in `amzn-s3-cur` (allowed), `cid_cur2` in a separate CID export bucket (not allowed). Fixed with a new `additional_cur_bucket_names` variable granting **read-only** `GetObject`/`ListBucket`/`GetBucketLocation`; the bucket name lives in gitignored `config/terraform.tfvars` so the public repo stays account-agnostic. Applied with `-target=module.mcp_athena.aws_iam_role_policy.lambda_permissions` — 0 added, 1 changed, 0 destroyed — and a before/after set-comparison of the inline policy confirmed **0 permissions lost, 6 gained, no Deny**. Verified after: `cid_cur2` query SUCCEEDED, $28.36 used / $111.99 unused. **Rule: registering a Glue table is not enough — check which bucket it points at.** |
 One QuickSight account per AWS account, so a new QuickSuite agent does not rename it. `UpdateAccountSettings` accepts only `AwsAccountId`, `DefaultNamespace`, `NotificationEmail` and `TerminationProtectionEnabled` — there is **no** `AccountName` parameter, verified across the .NET v4 and PHP API references. `DescribeAccountSettings` returns the name but nothing writes it back; it is fixed at `CreateAccountSubscription`. The only change path is unsubscribe + re-subscribe, which **deletes assets and users in that Region** — unacceptable six days from the demo. Whether the name renders anywhere a demo audience sees is **unverified**; it was found via API, not in the UI. Mitigations if it does surface: demo from the agent view only, give the *agent* a neutral name, frame the browser window. |

### On D6

Both providers restate data. Azure runs twice daily for the first five days of a
month because late charges land up to 72 hours after close; both providers
restate the open month continuously. Appending produces inflated totals that
nobody notices until someone reconciles against an invoice.

## Athena table

```sql
CREATE EXTERNAL TABLE focus_costs ( /* FOCUS 1.0 core + x_payload string */ )
PARTITIONED BY (provider string, billing_period string)
STORED AS PARQUET
LOCATION 's3://<bucket>/focus/'
TBLPROPERTIES (
  'projection.enabled'                 = 'true',
  'projection.provider.type'           = 'enum',
  'projection.provider.values'         = 'aws',          -- phase 2: 'aws,azure'
  'projection.billing_period.type'     = 'date',
  'projection.billing_period.range'    = '2025-01,NOW',
  'projection.billing_period.format'   = 'yyyy-MM',
  'projection.billing_period.interval' = '1',
  'projection.billing_period.unit'     = 'MONTHS',
  'storage.location.template'          = 's3://<bucket>/focus/provider=${provider}/billing_period=${billing_period}'
);
```

Phase 2 changes one line: the projection enum.

## AWS FOCUS schema — verified 2026-08-12

`aws bcm-data-exports get-table --table-name FOCUS_1_0_AWS` returns **48 columns**:
43 FOCUS spec + 5 AWS extensions (`x_CostCategories`, `x_Discounts`, `x_Operation`,
`x_ServiceCode`, `x_UsageType`).

Types that matter for the union:

- All cost columns (`BilledCost`, `EffectiveCost`, `ListCost`, `ContractedCost`,
  `ListUnitPrice`, `ContractedUnitPrice`, `ConsumedQuantity`, `PricingQuantity`) → `Number`
- `BillingPeriodStart/End`, `ChargePeriodStart/End` → `Timestamp`
- `Tags`, `x_CostCategories`, `x_Discounts` → **`Map`**

`FOCUS_1_0_AWS` exposes **no table properties**, so there is no granularity knob.
(`FOCUS_1_2_AWS` does: `TIME_GRANULARITY` with `HOURLY` default.) `FOCUS_1_0_AWS_PREVIEW`
is flagged `DEPRECATED` — do not use it.

## Deferred risk — read before declaring phase 1 done

A green phase 1 does **not** prove phase 2. With no Azure access these are **not
resolvable by us** — they stay open until an Azure tenant or a real customer export
appears. A hand-built mock cannot close them, because a mock has whatever types you
gave it.

**Now concrete, from comparing the verified AWS schema against Microsoft's published
1.0 column list:**

- **The FOCUS "core" is smaller than either provider's set.** AWS has
  `AvailabilityZone`, which Azure 1.0 does not. Azure has `BillingAccountType` and
  `SubAccountType`, which AWS does not. The curated table's column list must be the
  *intersection*, with the rest pushed into `x_payload`.
- **`Tags` will not union as-is.** AWS types it `Map`; Azure documents it as a JSON
  object, which in their CSV/Parquet is a string. `map<string,string>` and `string`
  cannot share a column — the transform must normalise both to a JSON **string**.

**Still fully unverified:**

- **Parquet numeric types.** AWS reports `Number` at the API level; the physical Parquet
  type (decimal vs double) and Azure's equivalent are both unconfirmed. A mismatch fails
  at read time, not at DDL time. **Highest-consequence unknown.**
- **Blob → S3 copy mechanism.** Azure Function on blob-created, scheduled pull, or object
  replication — none confirmed able to write to S3 directly.
- **Azure credentials in Lambda.** Service principal secret vs. workload identity
  federation. The federation path is unverified.

Mitigation available now: the `x_payload` JSON column and the `raw/` zone mean a type
surprise is fixed by re-running the transform, not by re-architecting.

## Sources

- [Understanding export delivery](https://docs.aws.amazon.com/cur/latest/userguide/dataexports-export-delivery.html) — AWS S3 path and manifest
- [Data Exports table dictionary](https://docs.aws.amazon.com/cur/latest/userguide/dataexports-table-dictionary.html) — FOCUS 1.0 / 1.2 tables
- [FOCUS cost and usage details file schema](https://learn.microsoft.com/en-us/azure/cost-management-billing/dataset-schema/cost-usage-details-focus) — Azure versions and columns
- [Create and manage Cost Management exports](https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/tutorial-improved-exports) — Azure blob layout, partitioning, restatement
- [Configure inbound JWT authorizer](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/inbound-jwt-authorizer.html) — Gateway discovery-URL requirement
