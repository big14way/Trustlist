# Hosting

The public marketplace, and what it runs on. The main track requires a
submission that is "publicly accessible during judging", so this is a
requirement rather than a convenience.

| piece | where | url |
|---|---|---|
| web app | Vercel | https://trustlistapp.vercel.app |
| API | Render, Docker from `./Dockerfile` | https://trustlist-api.onrender.com |
| database | Render Postgres, free plan | internal only |
| Yield Scout | Render | https://trustlist-yield-scout.onrender.com |
| Range Keeper | Render | https://trustlist-range-keeper.onrender.com |

Everything is on a free plan. Set up 31 August 2026.

## The database is a subset, and which parts

The local index is 6.4 GB. The hosted one holds what the site reads and
nothing else, copied by `scripts/sync_prod_db.sh`:

- **every agent**, all 321,772 of them, because the headline count has to be
  the real one and any agent page has to resolve
- **the newest score per agent**, not the 22.8 million rows of scoring
  history behind them, because no page reads history
- **a recent window of probes**, because the probe strip draws seven days
- **the trust and snapshot tables in full**, they are small

That comes to about 570 MB. Nothing is invented, nothing is rounded, and no
number on the hosted site differs from the number the local index would give
for the same question.

Refresh it before judging:

```
bash scripts/sync_prod_db.sh --probe-days 7
```

The table list is derived from the schema rather than typed out. It was
typed out once and `registry_stats` was left off it, which is where every
headline number comes from, so the hosted site cheerfully announced that the
prober had not completed its first scoring pass while holding 321,519
agents.

## The free tier failure that mattered, and what actually fixed it

The API flapped badly at first: **8 of 12 requests over one minute**, the
failures arriving as 404 with `x-render-routing: no-server`. Our own logs
were clean throughout, showing a normal start, migrations applied and no
errors, so the process was healthy and the platform's router was not sending
it traffic.

The cause was the number of free web services in the workspace. There were
eleven, ten of them running. Render's free web services share a monthly
instance hour allowance across a workspace, and eleven of them do not fit
into it.

This was not obvious and the first diagnosis was wrong in both directions.
The theory was raised, then withdrawn on the grounds that six of the other
services were already spun down and an idle service consumes nothing. Render
exposes no usage endpoint, so neither version could be checked directly.
Deleting five services settled it:

| | before | after |
|---|---|---|
| services in the workspace | 11 | 6 |
| health checks answered | 8 of 12 | 20 of 20 |

So the original theory was right and withdrawing it was the mistake. Worth
recording, because the lesson is not "free hosting is flaky", it is "free
hosting is a shared allowance and someone else's idle project is still
holding a share of it".

**Keep the workspace small.** Adding unrelated free services back will bring
this straight back, and it will look like our API breaking rather than like
a quota.

## Cold starts are still real

A free instance still spins down when idle and answers 404 for up to a
minute while it wakes. `.github/workflows/uptime.yml` pings all three
services every ten minutes, which keeps them warm and doubles as the uptime
monitor SPEC Section 30.7 asks for.

If the flapping ever returns and the workspace is already small, the fix
that removes the whole class of problem is a Starter instance at about seven
dollars a month. It needs a payment method on the workspace; without one the
API refuses with `invalid plan Starter. Plan requires payment information on
file`.

## Redeploying

Both the API and the agents deploy from `main` automatically. The web app:

```
cd web && vercel deploy --prod --token "$VERCEL_TOKEN"
```

Production environment variables live in the Vercel project, not in the
repository. `NEXT_PUBLIC_API_URL` points at the Render API;
`NEXT_PUBLIC_CHAIN_ID`, `NEXT_PUBLIC_HIRE_RAIL`, `NEXT_PUBLIC_PAYMENT_TOKEN`
and `NEXT_PUBLIC_TRUST_SNAPSHOT` carry the mainnet deployment.

## Next.js is pinned for a reason

Vercel refuses to deploy Next 15.4.6: it carries several critical
advisories, including remote code execution in the React flight protocol and
SSRF through middleware redirects. We are on 15.5.24, the patched line.

One moderate advisory remains, a bundled postcss that only Next 16.3.3
resolves. Taking a major version bump on deploy day was the larger risk, so
that upgrade is deliberately deferred rather than overlooked.
