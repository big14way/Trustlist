#!/usr/bin/env bash
# Generate docs/METHODOLOGY.md from the live /v1/methodology response, which
# serves the same constants the trust engine runs on. The spec requires the
# document and the page to agree; generating both from one source is the only
# way to guarantee that as thresholds change.
set -euo pipefail
cd "$(dirname "$0")/.."
API="${API:-http://localhost:8080}"

curl -sf "$API/v1/methodology" > /tmp/methodology.json || {
  echo "the api must be running to regenerate the methodology" >&2
  exit 1
}
curl -sf "$API/v1/stats" > /tmp/stats.json || true

python3 - <<'PY' > docs/METHODOLOGY.md
import json

m = json.load(open("/tmp/methodology.json"))
try:
    s = json.load(open("/tmp/stats.json"))
except Exception:
    s = {}

L, R, K = m["liveness"], m["reputation"], m["ranking"]
out = []
w = out.append

w("# How the numbers are made")
w("")
w("Generated from `GET /v1/methodology`, which serves the same constants the")
w("trust engine runs on. Regenerate with `bash scripts/gen_methodology.sh`.")
w("Do not hand edit: a threshold changed here would be a claim the code does")
w("not honour.")
w("")
if s.get("measured"):
    w(f"At the time of writing: {s['registered']:,} agents registered, "
      f"{s['live'] + s['flaky']:,} answering when probed, "
      f"{s['probes_total']:,} probes recorded, and {s['feedback']:,} reviews on "
      f"chain written by {s['reviewers']} distinct addresses.")
    w("")

w("## What kind of agent is it")
w("")
w(m["categories"]["how"])
w("")
w("| category | matches | meaning |")
w("|---|---|---|")
for c in m["categories"]["rules"]:
    w(f"| `{c['id']}` | {c['matches']} | {c['matched_agents_note']} |")
w("")
w(m["categories"]["caveat"])
w("")

w("## Is the agent alive")
w("")
w("Every agent's declared endpoints are resolved and called on a schedule, and")
w("the whole history is kept. Uptime is measured, not claimed.")
w("")
w("```")
w(L["formula"])
w("```")
w("")
w(f"- Probe interval: {L['probe_interval_secs'] // 60} minutes")
w(f"- Hosts serving many registrations: every {L['bulk_host_probe_interval_secs'] // 3600} hours")
w(f"- Probes required before a status is assigned: {L['min_probes_for_a_status']} "
  f"(or {L['min_probes_daily_cadence']} on the daily cadence)")
w(f"- Live: uptime at or above {L['live_threshold']}")
w(f"- Flaky: uptime between {L['flaky_threshold']} and {L['live_threshold']}")
w(f"- Latency factor reaches zero at {L['latency_ceiling_ms']} ms")
w("")
w(f"**Counts as alive.** {L['alive_http_statuses']}")
w("")
w(f"**Counts as down.** {L['dead_http_statuses']}")
w("")
w(f"**When the fault is ours.** {L['observer_outage_rule']}")
w("")

w("## Is the praise real")
w("")
w(R["scale"])
w("")
w("Every address that has left feedback starts at full weight and is multiplied")
w(f"down by each signal below. The floor is {R['weight_floor']} rather than zero:")
w("we downweight, we do not delete, so the product can always show how many")
w("reviews were seen next to how many were counted.")
w("")
w("| signal | weight | what it detects | why |")
w("|---|---|---|---|")
for p in R["penalties"]:
    w(f"| `{p['id']}` | x {p['factor']} | {p['detects']} | {p['why']} |")
w("")
w(f"**Clusters vote once.** {R['cluster_cap_rule']}")
w("")
w(f"**Prior strength.** m = {R['prior_strength']}, so a single glowing review does")
w("not outrank fifty ordinary ones.")
w("")
w(f"**When no score is published.** A score appears only once at least")
w(f"{R['min_evidence_to_publish']} full independent voice survives weighting.")
w("Below that the result would be almost entirely the prior, which is a guess")
w("about agents in general rather than evidence about this one. An agent with")
w("hundreds of reviews and no independent reviewer gets no score, and the")
w("interface says why.")
w("")

w("## How agents are ordered")
w("")
w("```")
w(K["formula"])
w("```")
w("")
w(K["default_filter"])
w("")

w("## How this can be wrong")
w("")
for k in m["known_weaknesses"]:
    w(f"- {k}")
w("")
w("## Being a good citizen")
w("")
w("Probes go out at one request every ten seconds per host, pooled for hosts")
w("serving many registrations, with a real user agent naming this project and")
w("a link to the source. Endpoints that answer 401, 402, or 403 are recorded as")
w("alive rather than retried harder.")
print("\n".join(out))
PY
echo "wrote docs/METHODOLOGY.md"
