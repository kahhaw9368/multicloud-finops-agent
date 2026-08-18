# Requirements — Multicloud FinOps Agent (FOCUS)

## Goal

A FinOps agent that answers cost questions across AWS and Azure through one
interface, using **FOCUS 1.0** as the common schema. Client is QuickSuite,
authenticating to an AgentCore Gateway with a Cognito M2M token.

Supersedes `.kiro/specs/deploy-ap-southeast-5-nonvpc/`. That spec's D6/T3
(Marketplace container image, ap-southeast-5 ECR path) disappear here because
`aws-api-mcp` is dropped.

## Why FOCUS

Each provider names and calculates cost differently. FOCUS normalises this at
the **data layer**, so one tool and one set of SQL recipes serve every provider.
The alternative — a tool per cloud — makes the model reconcile cross-provider
totals itself, which is where a cost agent invents numbers.

## Phasing

**Deadline: Thursday 2026-08-20.**

**Phase 0 — switch FOCUS on today.** Data Exports does not backfill, so a FOCUS
export created later permanently loses the intervening months. Nothing in the
demo reads it.

**Phase 1 — demo on CUR 2.0.** The existing `cur` export already has 11 months
of history (`2025-10` → `2026-08`). Stock `athena-mcp` reads it. Deployed in
us-east-1.

**Phase 1.5 — post-demo.** Accuracy hardening (modelled on uno-tam's routing,
forced metric selection, anti-hallucination contract and verifiability gate) and
`focus-mcp` once the FOCUS export has history worth querying.

**Phase 2 — Azure, additive.** Adds a data source, not a code path.

The seam that makes phase 2 additive — `provider` as a partition key, a tool that
speaks FOCUS rather than CUR columns — belongs to phase 1.5, not the demo.

> **Phase 2 is DESIGN-ONLY and currently unschedulable.** We have no Azure
> access of any kind — no tenant, no sandbox. So phase 2 cannot be built or
> validated, only designed against Microsoft's published schema. Unblocking it
> requires either an Azure tenant or a real FOCUS export (or representative
> sample) from the customer.

## What the demo has to achieve

The point is CelcomDigi buying into the idea of a custom FinOps agent **and** the
multicloud path. That splits into:

1. A customer persona interacts with QuickSuite only, and gets real answers from
   real data. No CLI, no console.
2. An architecture story for FOCUS + Azure that makes multicloud look inevitable
   rather than aspirational.

Accuracy hardening is explicitly **not** a demo goal — it is phase 1.5.

## Success criteria

### Phase 1
1. FOCUS 1.0 Data Export delivering to `raw/provider=aws/`.
2. Transform writes `focus/provider=aws/billing_period=YYYY-MM/`.
3. One Glue table, partition projection, **no crawler**.
4. Re-running the transform for a period does not change totals (replacement,
   not append).
5. Gateway reachable with a Cognito M2M token; `focus-mcp` and
   `cost-explorer-mcp` both answer.
6. QuickSuite connects and returns real figures from the deploying account.
7. No Isengard account identifier visible in anything shown on screen.

### Phase 2
8. Azure FOCUS 1.0r2 export landing in `raw/provider=azure/`.
9. Same transform produces `focus/provider=azure/...` with **no change** to
   `focus-mcp`, the table's column list, or any query recipe.
10. `provider` added to the projection enum; cross-provider totals are a single
    partition-pruned `GROUP BY`.
11. `azure-api-mcp` answers Azure resource-metadata questions.

## Constraints

- **FOCUS 1.0 only.** The one version stable on both providers — AWS offers
  FOCUS 1.0 and 1.2; Azure offers 1.0, 1.0r2 and 1.2-**preview**. FOCUS 1.2 is a
  later migration, not v1.
- **Azure pinned to `1.0r2`**, which formats dates with seconds per the spec.
- **Region ap-southeast-5** (Malaysia), non-VPC (`enable_vpc = false`) — no `ce`
  interface endpoint or AgentCore runtime data-plane endpoint there.
- **Public repo.** Customer names, account IDs and cost figures never land in
  this repo; they stay in the TAM KB.

## Out of scope

- FOCUS 1.2 migration.
- Cross-account (data collection → payer) topology. Invisible in the demo UX;
  belongs to the customer's real deployment, not this build.
- GCP or any third provider.
- Generic `call_aws`. Deliberately removed — a wide tool surface is the main
  driver of hallucinated cost answers.
