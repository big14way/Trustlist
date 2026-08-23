# How the numbers are made

Generated from `GET /v1/methodology`, which serves the same constants the
trust engine runs on. Regenerate with `bash scripts/gen_methodology.sh`.
Do not hand edit: a threshold changed here would be a claim the code does
not honour.

At the time of writing: 293,785 agents registered, 5,562 answering when probed, 1,719,021 probes recorded, and 29,511 reviews on chain written by 105 distinct addresses.

## What kind of agent is it

An agent's categories are inferred from the text its own owner wrote in its registration card: the name and description. A card must contain both an action word and the thing being acted on before a category is assigned, so 'track trust and alignment' does not become a monitoring agent while 'monitors a portfolio, positions and treasury' does.

| category | matches | meaning |
|---|---|---|
| `monitoring` | monitor, watch, track, or alert, together with wallet, position, market, price, portfolio, balance, liquidation, or treasury | watches markets, wallets, or positions and reports |
| `grid-trading` | grid, together with trade, order, bot, strategy, or range | runs automated orders within a set range |
| `health-factor` | health factor, liquidation, or collateral | protects a lending position from liquidation |
| `yield` | yield, apy, apr, farming, or staking | moves capital toward a better return |
| `rebalancing` | rebalance, liquidity range, lp position, or concentrated liquidity | manages a liquidity range and resets it |
| `pancakeswap` | pancakeswap or pancake | names PancakeSwap as the venue it works on |

This is a keyword rule over free text, not a claim about what the agent does. It will mislabel an agent whose description is vague, and it will miss one that describes its work in words we did not anticipate. An agent with no match is filed under other rather than guessed at. If you own an agent and we have it wrong, the fix is a clearer description in your card, and we will pick it up on the next pass.

## Is the agent alive

Every agent's declared endpoints are resolved and called on a schedule, and
the whole history is kept. Uptime is measured, not claimed.

```
liveness = 100 * (0.55*uptime_7d + 0.30*card_quality + 0.15*latency_factor)
```

- Probe interval: 30 minutes
- Hosts serving many registrations: every 24 hours
- Probes required before a status is assigned: 24 (or 6 on the daily cadence)
- Live: uptime at or above 0.9
- Flaky: uptime between 0.5 and 0.9
- Latency factor reaches zero at 5000 ms

**Counts as alive.** any status below 500 except 404. A 401, 402, or 403 means the endpoint answered and wants payment or a key, which is a working agent.

**Counts as down.** 404, any 5xx, and every transport failure: dns, tls, connection refused, timeout.

**When the fault is ours.** an hour in which we sent more than 100 probes and fewer than 5 percent succeeded is treated as our outage, not theirs. Those hours are excluded from uptime and shown as no data. The probes are never deleted.

## Is the praise real

The registry stores a signed int128 with a per event decimals field and defines no scale. We divide by 10^decimals, clamp into 0..100, and read that as a percentage. Every feedback event on BSC today lands inside that range once scaled, so the clamp is a guard rather than a reinterpretation.

Every address that has left feedback starts at full weight and is multiplied
down by each signal below. The floor is 0.02 rather than zero:
we downweight, we do not delete, so the product can always show how many
reviews were seen next to how many were counted.

| signal | weight | what it detects | why |
|---|---|---|---|
| `funding_cluster` | x 0.25 | five or more reviewers whose first transaction was paid for by the same wallet | Somebody who pays the gas for a crowd of reviewers is running them, not meeting them. This is the signal that catches the farm operating on BSC today. |
| `shared_funder` | x 0.5 | two to four reviewers sharing a funder | A pair can be colleagues or one person with two wallets. Suspicious, not damning. |
| `coreview_ring` | x 0.35 | reviews at least 20 of the same agents as 3 or more other reviewers | The farm on BSC is patient: it drips reviews out over weeks rather than firing them in a burst, so a timing detector misses it entirely. What it cannot hide is that the same addresses keep showing up on the same agents. |
| `one_shot` | x 0.3 | exactly one review, and fewer than five transfers ever | An address created to say one thing and then never used again is not a participant. |
| `no_other_activity` | x 0.5 | fewer than five transfers out, ever | Reputation should cost something. An address with no other life on chain paid nothing to have an opinion. |
| `single_value_only` | x 0.5 | three or more reviews that are all the identical score | A reviewer who has never once distinguished between two agents is not evaluating them. |
| `fresh_address` | x 0.5 | funded less than 24 hours before its first review | Wallets created just in time to vote are the oldest trick there is. We measured where the line actually falls on this registry: addresses that reviewed within a day of being funded average under three other transfers ever, while those funded a week or more beforehand average sixty three. A day is where provisioning stops and real use starts. |
| `reciprocal` | x 0.4 | rates an agent whose owner rates an agent it owns | Mutual praise between two owners is an arrangement, not evidence. |
| `high_revocation` | x 0.3 | three or more reviews, at least half later revoked | Feedback written and withdrawn is a way to be counted in a snapshot and then vanish. |

**Clusters vote once.** For each agent, reviewers are grouped by cluster and a cluster contributes one voice at the weight of its strongest member. Without this, twenty downweighted addresses still outvote one real reviewer by sheer count.

**Prior strength.** m = 5.0, so a single glowing review does
not outrank fifty ordinary ones.

**When no score is published.** A score appears only once at least
1.0 full independent voice survives weighting.
Below that the result would be almost entirely the prior, which is a guess
about agents in general rather than evidence about this one. An agent with
hundreds of reviews and no independent reviewer gets no score, and the
interface says why.

## How agents are ordered

```
rank_score = 0.45*liveness + 0.35*trust
```

Only agents that earned a status by being probed enough appear by default. The measuring majority is reported as a count, not listed as if it were ranked.

## How this can be wrong

- Funding traces follow only the first inbound transfer. An operator who funds each reviewer from a fresh intermediate wallet would not form a cluster under this rule.
- The co-review signal needs a reviewer to overlap with several others. Two addresses working as a pair can stay below it.
- We cannot enumerate a reviewer's full transaction history cheaply, so 'barely transacts outside the registry' uses transfer counts rather than every contract call.
- A high trust score still means only that independent looking addresses said good things. It is not a guarantee about future work.
- Uptime is measured from one vantage point. An endpoint that is reachable from elsewhere but not from us reads as down, which is why the observer outage rule exists and why we publish the probe history rather than only the summary.
- Agents that are new or rarely probed are excluded from the default ranking rather than scored badly, so a good new agent is invisible until it has been measured. That is deliberate and it is a cost.

## Being a good citizen

Probes go out at one request every ten seconds per host, pooled for hosts
serving many registrations, with a real user agent naming this project and
a link to the source. Endpoints that answer 401, 402, or 403 are recorded as
alive rather than retried harder.
