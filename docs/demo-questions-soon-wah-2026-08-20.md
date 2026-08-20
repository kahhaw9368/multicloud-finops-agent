# Demo questions — answering Soon Wah's email, level by level

**Thursday 20 August 2026** · Amazon Quick Suite → `CelcomDigi FinOps Analyst`

Soon Wah's email asked about EKS rightsizing at **three levels** and offered to have the
rightsizing part run first. This is that running order — his three levels in his order,
each with the exact question to type and the value to expect on screen.

All figures verified against live queries **2026-08-18 15:45 +08**.

> **Quote ratios, not August dollars.** Every dollar figure below is mid-month accrual and
> will be larger on Thursday. The *percentages* are stable. Say "about 80% of pod spend is
> requested and never used", never "$157.71".

---

## ⚠️ Read this first — a question in the old script no longer fails

`demo-script-2026-08-20.md` Q7 asks *"How over-provisioned is the platform-prod cluster?"*
and expects the agent to **decline** because the cluster has no Container Insights.

**It will not decline. It will answer, correctly, that platform-prod is 90.0% wasted.**

Split cost allocation in `cid_cur2` derives requests-versus-usage from the EKS control
plane, **not** from Container Insights. So pod-level *cost* waste is available for all four
clusters, including the three with no instrumentation at all.

That is a better capability than the email promised — but it breaks the "must decline"
moment unless the question specifically asks for something only CloudWatch can give. The
corrected wording is Q6 below.

---

## Level 1 — Cluster

> *"For each EKS cluster, how much pod cost was requested but never used in August 2026?"*

**Expect 4 clusters with data:**

| Cluster | Nodes | Pods | % of pod spend wasted |
|---|---|---|---|
| `platform-prod` | 7 | 21 | **90.0%** |
| `platform-nonprod` | 7 | 28 | **89.9%** |
| `demo-cluster` | 2 | 24 | 67.1% |
| `test-old-cluster` | 2 | 45 | 63.7% |

**Say:** the two `platform-*` clusters are the worst at ~90%, and neither is instrumented —
so this number comes from billing data alone. No agent in the cluster, no metrics pipeline,
nothing for their platform team to install. That is the cheapest possible starting point.

### Follow-up — the idle control planes

> *"Which individual resources cost the most in July 2026?"*

**Expect** three EKS clusters at exactly **$446.40** each — `managednodes-quickstart`
(us-east-2), `eks-workshop` (ap-southeast-5), `test-old-cluster` (us-east-1). Roughly
**$893/month** for the two that look non-production.

⚠️ **Add the qualifier immediately:** *"the cost is measured; 'non-production' is inferred
from a name."* This is the most important sentence in the demo.

⚠️ **Do not drill into the RDS row** — `petclinic-database` carries account
`324037304703`. It is your own linked account, but explaining that mid-demo costs you the
thread.

---

## Level 2 — Pod / workload

His explicit first bullet was *CPU and memory requests versus actual usage*. Answer it from
**both** directions, and name which source each comes from.

### 2a — What the over-provisioning costs (all clusters)

> *"Which pods are over-provisioned, and what is it costing us?"*

**Expect roughly 80% of pod-attributed spend** requested and never used, with
`metrics-server` replicas at the top — each requesting roughly **19×** what it uses.

**Say:** nobody chose that. It is the upstream default manifest, replicated across four
clusters. This is the class of finding that pays for the exercise, because the fix is a
one-line resource limit, not an architecture change.

### 2b — How far off the request is (instrumented clusters only)

> *"What percentage of its CPU request does the demo-web pod actually use?"*

**Expect ≈ 0.06%** — about **1,700× over-provisioned** — via a CloudWatch metric-math
expression.

**Say this pairing explicitly, it is the core of the whole demo:**

> **CUR tells you the over-provisioning costs money. CloudWatch tells you the pod uses
> 0.06% of what it asked for. One gives the impact, the other the corrective action.
> Neither alone answers the question.**

**The agent must state the one-month limitation.** The split cost allocation table holds
**2026-08 only** — Data Exports does not backfill. If it presents this as a trend, correct
it out loud.

---

## Level 3 — Node

**This is the level with no question in the old script.** It is answerable, and the result
is the most visual finding in the set.

### 3a — Node-level waste and pod density

> *"Break down pod cost by node for August 2026 — which nodes are paying for capacity
> nobody uses?"*

**Expect 18 nodes.** The shape matters more than any single row:

| Node | Pods | % wasted | |
|---|---|---|---|
| `i-0459d9c3e9638cdfd` | **1** | **95.0%** | one `metrics-server` pod, whole node |
| `i-0a963d876ec3334a3` | **1** | **95.0%** | same, `platform-prod` |
| `i-09b1505c8b4ffd533` | **1** | **95.0%** | same, `platform-nonprod` |
| `i-0fdccadbd11a19311` | 6 | 82.3% | |
| `i-01819288f106e5140` | 30 | 65.0% | |
| `i-07e8413aaa19044e1` | **17** | **36.6%** | best-packed node in the estate |

**Say:** six nodes are running a single pod each, and that pod is `metrics-server`. A whole
node, 95% of its cost unused. Then point at the last row — **the best-packed node runs 17
pods and wastes 36.6%.** Same estate, same day.

> **That spread from 95% down to 36.6% is the bin-packing conversation, and the agent got
> there from billing data.**

### 3b — Node utilization (instrumented clusters only)

> *"What is the average CPU and memory utilization of the demo-cluster nodes?"*

**Expect** CPU **avg 3.45%**, peak 53.45% · Memory **avg 39.27%**, peak 63.29%
(verified 2026-08-20 13:05 +08). Peaks drift day to day; the averages are stable.

⚠️ **This question failed in rehearsal and the persona was patched for it.** The agent
tried a per-node query, built the `{NodeName, InstanceId}` pairing itself from the Level 3a
Athena instance IDs, got it backwards, matched nothing, and reported *"metrics are not
available for demo-cluster"* — a false negative on the one cluster that **is** instrumented,
contradicting 3a and Q6. The persona now mandates `{ClusterName}` alone for cluster-level
phrasing and forbids inventing the pairing. **Re-test this question after pasting the
persona.** If it still says unavailable, fall back to asking *"using the ClusterName
dimension only…"*.

**Say:** the CPU/memory asymmetry is the useful part — memory is **11× more utilised than
CPU**, so these nodes are memory-shaped and the CPU request is the thing that is wrong.
That distinction is what stops a rightsizing exercise from breaking something.

### 3c — Where you stop, and say so

**Do not** offer a bin-packing plan or an instance-type recommendation. His email framed
node level as *"after pod rightsizing"* — which is correct sequencing and worth affirming
out loud, because it tells him you read the email properly.

**Say:** rightsize the pods first. Node consolidation against wrong requests just
provisions the wrong capacity more efficiently.

---

## The two questions that must decline

### Q6 (corrected) — utilization on an uninstrumented cluster

> *"Show me the CPU utilization over time for the platform-prod cluster."*

**It must say platform-prod is not instrumented.** Verified: `platform-prod`,
`platform-nonprod` and `test-old-cluster` all return **0 datapoints**; only
`demo-cluster` returns data (32 datapoints over 24h).

Note the wording — *utilization over time*, not *"how over-provisioned"*. The second form
is answerable from CUR and will not fail.

**Say:** zero datapoints and zero usage look identical to a naive tool. This one knows the
difference. **The agent's ceiling is the data it can read** — and notice it still gave you
the cost answer for that same cluster one question ago. Different source, different
coverage, and it keeps them straight.

### Q7 — Savings Plans coverage

> *"What is our Savings Plans coverage?"*

**It must decline.** No tool backs it. Verified on this account: 0 Savings Plans, 0 EC2
RIs, 0 RDS RIs, and Cost Explorer's purchase recommendation returns null.

**Say:** it would be trivial to make this answer *something*. We deliberately did not — you
would act on the guess. Then move to the SP/RI talking points in
`demo-script-2026-08-20.md`.

---

## The two limits to state before he finds them

**No VPA target values.** The agent will tell you a pod uses 0.06% of its request and show
the observed distribution. It will not hand you the number to set. That stays a VPA,
StormForge, Datadog or human decision — AWS has no first-party VPA for EKS pods, and
Compute Optimizer covers ECS-on-Fargate but not Kubernetes pods.

**Utilization only where instrumented.** One of four clusters. Frame this as the pitch, not
the weakness: cost data was connected first, which is why it could talk about spend;
Container Insights was added last week, which is what made utilization answerable. **If
their utilization lives in Datadog rather than CloudWatch, that is another connector — not
a different product.**

---

## Runtime

Nine questions, roughly 12–15 minutes conversational. Levels 1→3 are the demo; the two
declines are the argument.

| Warm-up | 30 min before: ask Level 1 and 2b to wake the Lambdas and confirm the connector |
| Fallback | "Query started" then stops → say *"check the query status"* (chaining, not data) |
