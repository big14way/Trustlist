# Yield Scout

A read only PancakeSwap agent. It reads live V3 pool data from PancakeSwap's
own explorer API, computes what each pool actually paid its liquidity
providers over the last 24 hours and 7 days, and reports better risk adjusted
options for a given asset with a written reason.

It never holds funds, never asks for an approval, and never signs anything.
The worst case for a user is that they disagree with the ranking.

## Why the ranking is not just "highest APR"

Fee APR alone rewards pools that are about to stop paying. A pool with a
sudden spike in volume shows a huge annualised number that will not survive
the week, and a pool with very little liquidity shows a high rate that
collapses the moment somebody adds to it. So the score combines:

- **fee return**, annualised from real fees paid over real TVL
- **consistency**, the 7 day rate against the 24 hour rate, so a pool that
  has been paying steadily beats one that spiked yesterday
- **depth**, so a pool too thin to enter without moving the price is ranked
  down rather than celebrated
- **turnover**, volume against TVL, because liquidity that nobody trades
  against earns nothing no matter how large it looks

Every input is shown alongside the answer so the user can disagree with the
weighting rather than having to trust it.

## Endpoints

- `GET /.well-known/agent.json` the ERC-8004 registration card
- `GET /health` liveness
- `GET /pools` the ranked table with every input visible
- `GET /advise?asset=CAKE` the recommendation for one asset, with reasoning

## Running it

    python3 agents/pancake-yield/server.py

Data source: `https://explorer.pancakeswap.com/api/cached/pools/v3/bsc/list/top`,
PancakeSwap's own explorer API. No key required. If it is unreachable the
agent says so and serves nothing rather than serving stale numbers.
