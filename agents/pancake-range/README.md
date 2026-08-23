# Range Keeper

Watches a PancakeSwap V3 concentrated liquidity position on BNB Smart Chain
and says when it has stopped earning, how far the price has drifted, and what
range would put it back to work.

## What it will not do

It does not execute, and it does not ask for an approval. Moving a range
means withdrawing and re-adding liquidity, which should happen inside a spend
cap the owner sets and can revoke. Until that path exists, this agent
proposes and the owner decides.

## Why it often says "wait"

A keeper that rebalances on every wobble loses its owner money: each move
costs gas and turns a paper loss into a real one. So it distinguishes between
a price that has just brushed the edge of the range and one that has left it
properly, and only recommends acting past a drift worth paying for.

It also preserves the width of the range. The owner chose how concentrated to
be, and a keeper that quietly widens or narrows that is making a decision it
was not asked to make.

## Endpoints

- `GET /.well-known/agent.json` the ERC-8004 registration card
- `GET /health` liveness, including whether the chain is reachable
- `GET /position?id=7238953` the full analysis for one position

## Reading positions

PancakeSwap Infinity has no subgraph, so positions come straight from the
contracts. The addresses were verified on BSC mainnet rather than copied
from a page: the position manager at
`0x46A15B0b27311cedF172AB29E4f4766fbE7F4364` answers `name()` with
"Pancake V3 Positions NFT-V1".

    python3 agents/pancake-range/server.py
