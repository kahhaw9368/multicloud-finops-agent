# Demo script — CelcomDigi multicloud FinOps agent
**Thursday 20 August 2026** · Amazon Quick Suite → `CelcomDigi FinOps Analyst`

All figures verified against live queries **2026-08-15 09:35 +08**. Closed months are
stable and will not move. **August is still accruing** — it went from `$1,744.47` on
14 Aug to `$2,083.43` on 15 Aug, so never quote an August total as an expected value.

Two design rules behind this script:

- **Fixed periods, never rolling windows.** Ask about "July 2026", not "the last three
  months" — a rolling window changes between rehearsal and performance.
- **Two questions must FAIL.** Q7 and Q8 exist so the agent visibly declines. That is the
  credibility moment, not a gap.

---

## The arc

| # | Question | What it proves |
|---|---|---|
| 1 | Monthly trend | The chain works, and reconciles to Cost Explorer |
| 2 | Why the Jun→Jul jump | It explains, not just reports |
| 3 | Bedrock token split | CUR answers what Cost Explorer cannot |
| 4 | Most expensive resources | Finds waste unprompted |
| 5 | Which pods are over-provisioned | Soon Wah's level 1, in dollars |
| 6 | How much of its request does a pod use | The measurement, not the inference |
| 7 | An uninstrumented cluster | **Must decline** |
| 8 | Savings Plans coverage | **Must decline** |

Runtime roughly 15 minutes at a conversational pace. Q1–Q6 are the demo; Q7–Q8 are the
argument.

---

## Q1 — "What did we spend each month since October 2025?"

**Expect 11 rows.** Anchors to check on screen:

```
2025-10  1,789.58      2026-02  2,596.95      2026-06  3,502.50
2025-11  1,991.06      2026-03  3,187.69      2026-07  4,182.48
2025-12  2,043.07      2026-04  3,466.60      2026-08  (accruing - ignore)
2026-01  2,247.62      2026-05  3,700.47
```

**Say:** every figure reconciles to Cost Explorer to the cent. That is the point of
opening here — before we discuss anything clever, the numbers are right.

**If it stalls after starting the query:** it fired `start_query_execution` and did not
poll. Say "check the query status" and it will continue. Not a data problem.

## Q2 — "Why did costs increase from June to July?"

**Expect** `$3,502.50 → $4,182.48`, **+19.4%**, decomposed. The three drivers account for
**87% of the $679.98 increase**:

| Service | June | July | Δ |
|---|---|---|---|
| Bedrock | 164.36 | 423.31 | **+258.95** |
| EKS | 1,368.00 | 1,585.41 | **+217.41** |
| EC2 | 328.29 | 440.23 | **+111.94** |
| DevOpsAgent | — | 54.42 | +54.42 (new) |

**Say:** this is the difference between a dashboard and an analyst. A chart shows the
line going up. This attributes 87% of the rise to three services and names a fourth that
appeared for the first time.

## Q3 — "Split our Bedrock spend in July into input, output and cache tokens."

**Expect:** input `$5.89`, output `$95.51`, **cache `$321.91`**.

**Say:** cache tokens are **76% of Bedrock spend and 55× the input cost**. Cost Explorer
can group by usage type but cannot bucket-and-sum like this. This is the first answer in
the demo that is *only* possible because we query CUR with SQL.

## Q4 — "Which individual resources cost the most in July 2026?"

**Expect** QuickSight application ≈ `$792.50`, then **three EKS clusters at exactly
`$446.40` each** — `managednodes-quickstart` (us-east-2), `eks-workshop`
(ap-southeast-5), `test-old-cluster` (us-east-1) — then Bedrock, then RDS.

**Say:** three identical `$446.40` charges are EKS control planes. One is called
`test-old-cluster`. Nobody asked the agent to find waste; it fell out of a
resource-level question. That is roughly **$893/month** for two clusters that look
non-production.

⚠️ **Then immediately add the honest qualifier** — this is the most important sentence in
the demo: *"the cost is measured; 'non-production' is inferred from a name. The agent
says so, and tells you what evidence would confirm it."*

⚠️ **Do not drill further into the RDS row.** `petclinic-database` carries account
`324037304703`, which is not this account and is unexplained. See T15.

## Q5 — "Which pods are over-provisioned, and what is it costing us?"

**Expect** `$28.36` used against `$111.99` requested-but-unused for August 2026 — about
**80% of pod-attributed spend paid for capacity never touched.** Top rows:

| Pod | Used | Unused |
|---|---|---|
| `amazon-cloudwatch/cloudwatch-agent-fvxp4` | 2.16 | **9.73** |
| `kube-system/metrics-server-…` ×4 | ~0.45 each | ~8.5 each |
| `kube-system/ebs-csi-node-l2ksp` | 0.36 | 3.84 |

**Say:** four `metrics-server` replicas each requesting ~19× what they use. Nobody chose
that — it is the default manifest. This is EKS split cost allocation data, and it is
Soon Wah's first bullet answered in dollars.

**The agent must state the one-month limitation.** If it presents this as a trend, correct
it out loud — that table holds August 2026 only.

## Q6 — "What percentage of its CPU request does the demo-web pod actually use?"

**Expect ≈ 0.06%**, via a CloudWatch metric-math expression.

**Say:** roughly **1,700× over-provisioned**, and this is *measured* utilization, not
inferred from cost. Pair it with Q5 explicitly: **CUR tells you the over-provisioning
costs $111.99; CloudWatch tells you the pod uses 0.06% of what it asked for.** One gives
the impact, the other the corrective action. Neither alone answers the question.

## Q7 — "Show me the CPU utilization over time for the platform-prod cluster."

**It must say the cluster is not instrumented.** Only `demo-cluster` runs Container
Insights (32 datapoints/24h); `platform-prod`, `platform-nonprod` and `test-old-cluster`
all return zero datapoints.

⚠️ **Wording matters here — do not ask "how over-provisioned is platform-prod".** That
form is answerable from `cid_cur2` split cost allocation, which derives requests-versus-usage
from the EKS control plane rather than Container Insights, and the agent will correctly
report **90.0% wasted**. Asking for *utilization over time* is what isolates the
CloudWatch-only capability. Verified 2026-08-18.

**Say:** zero datapoints and zero usage look identical to a naive tool. This one knows the
difference and says so — and notice it still answered the *cost* question for this same
cluster. Different source, different coverage, kept straight. **The agent's ceiling is the
data it can read** — that is the frame for the whole engagement, and it lands better as a
demonstrated limit than as a
slide.

🚨 **If it returns a utilization percentage or a time series here, stop using it for
utilization questions** — the T12D instrumentation-coverage rule did not take. A *cost*
figure is not the failure case; that one is real.

## Q8 — "What is our Savings Plans coverage?"

**It must decline.** No tool backs it.

**Say:** it would be trivial to make this answer *something*. We deliberately did not.
An agent that guesses at commitment coverage is worse than one that says it cannot see —
because you would act on the guess. Then move to the talking points below.

---

# Talking points — Savings Plans and Reserved Instances

Use after Q8. **Do not open a console to show this; there is nothing to show.**

**Why it is not in the demo.** Verified on this account: **0 Savings Plans, 0 EC2
Reserved Instances, 0 RDS Reserved Instances**, and Cost Explorer's purchase
recommendation returns null. There is nothing to demonstrate — which is honest and also
convenient, because it keeps the conversation on their estate rather than ours.

**It splits into two problems, and only one needs new plumbing.**

*Analysis* — coverage, utilization, waste, expiry dates — is already in CUR
(`savings_plan_*` and `reservation_*` columns). The agent could compute it today with
SQL, sliced per account, per service, per instance family. No new tool.

*Recommendation* — what to buy, at what term, what hourly commitment — is **not**
derivable from CUR. It comes from AWS's own optimizer over a 7, 30 or 60-day lookback.
That needs eight Cost Explorer operations: SP and RI coverage, SP and RI utilization,
SP utilization details, both purchase recommendations, and
`StartSavingsPlansPurchaseRecommendationGeneration` — because recommendations are
generated asynchronously, then retrieved.

**Three things worth saying because they show you have thought past the demo:**

1. **Commitments are shared across the organisation**, so coverage must be computed at
   payer scope. `AccountScope` is a real API parameter and getting it wrong produces
   confident nonsense in a multi-account estate. Theirs is multi-account.
2. **A recommendation is a point-in-time optimizer output, not a fact.** A 7-day lookback
   over an atypical week misleads. Whatever we build states its lookback.
3. **Read-only, always.** A commitment is a one-to-three-year contract. The agent supplies
   the recommendation and its assumptions; a human signs.

**The strongest line, and it is a hypothetical you cannot show:** on an estate with real
Savings Plans, `UnblendedCost` and `NetAmortizedCost` can differ by 30% or more. On this
demo account they are byte-identical, because there is nothing to amortise — so an agent
that silently picks the wrong metric *cannot* be caught here. On theirs it would be a
wrong-answer generator. **That is why the accuracy work is the next phase, and why
commitments are where it matters most.**

---

# Talking points — Cost Optimization Hub

**It is enabled on this account and returns real data**, but is deliberately **not wired
to the agent yet.**

```
$230.23/month total, 8 recommendations
  Stop              petclinic-database (RDS)   $188.34   effort: Low
  MigrateToGraviton EC2 ×4                      $28.39   effort: VeryHigh
  Rightsize         EC2 ×2                      $13.40   effort: Medium
  Delete            EBS volume ×1                $0.10
```

**The distinction that makes it worth adding: COH returns an *action*; everything else
returns a *fact*.** Show the same resource two ways:

| | |
|---|---|
| The agent said | *"RDS right-sizing — evaluate if `petclinic-database` needs its current instance size"* |
| COH says | **Stop** `petclinic-database`, **$188.34/month**, effort **Low** |

Same resource. One is defensible evidence; the other is a decision. COH has utilization
telemetry the agent does not.

**Now the part that matters for Soon Wah — and say this before he asks:**

**COH returns zero EKS recommendations.** No control plane, no nodes, no pods. Verified.
So COH does **not** answer his three levels. Its value is the *other* estate — EC2, RDS,
EBS, Lambda — which is where their spend actually concentrates.

**And the reverse, which is the more interesting half:** the agent's own headline finding
— roughly $893/month of idle EKS control planes — **does not appear in COH at all.**
COH does not evaluate control-plane idleness.

**So neither source is complete.** The agent found something real that AWS's own engine
misses; AWS's engine quantified something the agent could only gesture at. That is the
argument for connecting both, and it is a much better argument than "we should add COH."

**Roadmap framing:** one Cost Explorer-style Lambda,
`cost-optimization-hub:ListRecommendations`. Same pattern as the CloudWatch tool added
last week. Additive, not a re-architecture.

---

# Before you present

- [ ] Ask Q1 and Q6 as a warm-up ~30 minutes before, to wake the Lambdas and confirm the
      connector is healthy.
- [ ] **T15 leak check** — Cognito domain reads `finops-mcp-demo-aabe23` (safe), but
      confirm nothing on screen shows the account ID, and decide what to say if anyone
      asks about `324037304703`.
- [ ] Have `design.md`'s architecture diagram open in a second tab. Q7's answer is the
      natural cue to switch to it.
- [ ] Do not ask anything with a rolling window, and do not quote an August total.

# If something breaks

| Symptom | Almost certainly |
|---|---|
| "Query started" then stops | Chaining failure — say "check the query status" |
| Tool not found | Connector actions unlinked — Q1 in warm-up catches this |
| Confident *utilization %* on Q7 | Persona not applied; skip utilization questions (a cost figure is correct) |
| Pod query fails on permissions | The `cid_cur2` bucket IAM (T12E) — should be fixed |
| Numbers slightly off on August | Expected, it accrues. Pivot to a closed month |
