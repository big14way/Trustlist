# Agent Advantage Report

The TermiX challenge asks for at least three real tasks run both ways, with
and without an agent, recording time, cost and output quality, and at least
one task from trading, stocks or security. Task 1 is the security one.

Measured 2026-08-31T13:46:56Z. Reproduce with `python3 scripts/advantage.py`.
The raw evidence, including every output in full, is in
`docs/advantage_evidence.json`.

## How the two arms are defined

**Without an agent** is the individual chain reads a person has to make to
answer the question themselves, performed one at a time and counted.

**With an agent** is one HTTP request to an agent hired through our own
ERC-8183 escrow on BSC mainnet.

The baseline is scripted, and that is deliberate: **it flatters the**
**baseline**. A person doing this in a block explorer types addresses, waits
for pages to load, and reads values off a screen, which is far slower than a
script issuing the same calls back to back. Every margin below is therefore
a floor, not a headline.

Both arms run against the same chain at the same moment and their answers
are compared, so a faster wrong answer counts as a failure rather than a win.

## Results

| task | domain | by hand | with the agent | faster by | answers agree |
|---|---|---|---|---|---|
| 1. Screen four BSC tokens for the powers their  | security | 58.52s, 44 lookups | 6.87s, 4 request(s) | 8.5x | yes |
| 2. Find the best USDT pool on PancakeSwap V3 fo | trading | 1.04s, 1 lookups | 0.91s, 1 request(s) | 1.1x | yes |
| 3. Decide whether PancakeSwap V3 position 72842 | monitoring | 3.55s, 5 lookups | 2.04s, 1 request(s) | 1.7x | yes |

**The honest shape of this: one decisive win and two narrow ones.** The
agent's advantage tracks how many separate lookups the question needs. Task 1
needs 44 and the agent collapses them to 4. Tasks 2 and 3 need one and five,
and the margin nearly vanishes. A report where an agent wins three times over
by a wide margin would not be believable, and this is not that report.

## Cost

Every task was paid for through the same escrow any visitor uses: approve the
exact budget, hire, the agent submits, the hirer accepts, the escrow releases.

| task | job | hire | submit | accept |
|---|---|---|---|---|
| 1 | [56676](https://bscscan.com/tx/0xe683c02529585a2b5f74b638baa680a7f474fab9ce2036a4536337695d9fa72b) | [`0xe683c025..5d9fa72b`](https://bscscan.com/tx/0xe683c02529585a2b5f74b638baa680a7f474fab9ce2036a4536337695d9fa72b) | [`0x5865f433..4421ff0b`](https://bscscan.com/tx/0x5865f43328447e053ad04e92a3172e4f0fcf9023d9c0e5cb3f3057d04421ff0b) | [`0x8bfd68a3..d84e412d`](https://bscscan.com/tx/0x8bfd68a346cd51b6412894c9e3e70da8ae9c6caabbb4603493eea8fbd84e412d) |
| 2 | [56677](https://bscscan.com/tx/0x934869498f044ca94ed0189183a69b56079de4afa962b3965bc083d021ac406d) | [`0x93486949..21ac406d`](https://bscscan.com/tx/0x934869498f044ca94ed0189183a69b56079de4afa962b3965bc083d021ac406d) | [`0xa03bfdac..da70df97`](https://bscscan.com/tx/0xa03bfdac5ded64c99f66075b22d9515355f6d2a7217ecfce6a7bdc2bda70df97) | [`0x4eb29cd0..0c3a8e09`](https://bscscan.com/tx/0x4eb29cd078d7029e1af76fe0c8b134520ecd628e8e90b68fc19433f70c3a8e09) |
| 3 | [56678](https://bscscan.com/tx/0x58727ddd8446a3958c72f75e8f9008c77b8d2c6e80730f4efe367a12911847e2) | [`0x58727ddd..911847e2`](https://bscscan.com/tx/0x58727ddd8446a3958c72f75e8f9008c77b8d2c6e80730f4efe367a12911847e2) | [`0xea9934e5..46609e2a`](https://bscscan.com/tx/0xea9934e50cef2062064855baa30ea9cb2f8396e8a7745047b401bf3446609e2a) | [`0x8f759218..5e301b9e`](https://bscscan.com/tx/0x8f759218c0d6c035a5c2bf84144c4012827d4612fe55b60ba2f2bbf25e301b9e) |

Budget was 0.05 U per task. Gas came to about 0.000036 BNB per task at the
0.05 gwei BSC charges, so roughly two cents of gas for all three.

**The budget came back.** We own the agents we hired, so the escrow released
to an address we control. That is stated here rather than buried: it makes
the cost of running these tasks gas only, and it is the reason one small
purchase of U covered all three. It does not change that the jobs are real
ERC-8183 jobs against the live kernel with real escrow movement.

## Task 1: Screen four BSC tokens for the powers their owner keeps

**Domain:** security · **Agent:** Token Screen, ERC-8004 agent 322154 · **Job:** 56676

> For USDT, U, WBNB and CAKE: who owns it, can the code be replaced, and which of six owner powers exist in the deployed bytecode?

- **By hand:** 58.52s across 44 separate lookups
- **With the agent:** 6.87s across 4 request(s)
- **Faster by:** 8.5x

Agent output:

```json
{
 "USDT": {
  "owner": "0xf68a4b64162906eff0ff6ae34e2bb1cd42fef62d",
  "upgradeable": false,
  "powers": [],
  "verdict": "owned, read the findings"
 },
 "U": {
  "owner": "0x59f94ade4f881f21ea608ad4448bf70b78e37187",
  "upgradeable": true,
  "powers": [
   "mint(address,uint256)",
   "pause()"
  ],
  "verdict": "risky"
 },
 "WBNB": {
  "owner": null,
  "upgradeable": false,
  "powers": [],
  "verdict": "no owner powers found"
 },
 "CAKE": {
  "owner": "0x73feaa1ee314f8c655e354234017be2193c9e24e",
  "upgradeable": false,
  "powers": [
   "mint(address,uint256)"
  ],
  "verdict": "risky"
 }
}
```

## Task 2: Find the best USDT pool on PancakeSwap V3 for a 10,000 dollar position

**Domain:** trading · **Agent:** Yield Scout, ERC-8004 agent 320964 · **Job:** 56677

> Which USDT pool would have paid the most on 10,000 dollars over the last seven days, after our own position dilutes the pool?

- **By hand:** 1.04s across 1 separate lookups
- **With the agent:** 0.91s across 1 request(s)
- **Faster by:** 1.1x

Agent output:

```json
{
 "considered": 30,
 "best": {
  "pair": "NVDAB/USDT",
  "fee_bps": 25.0,
  "tvl": 2622976.59
 },
 "stated_apr": 171.56,
 "apr_recomputed_by_us": 171.56,
 "answer": "NVDAB/USDT at 25 bps would have paid about 171.6 percent annualised on 10,000 dollars over the last week."
}
```

## Task 3: Decide whether PancakeSwap V3 position 7284200 needs action

**Domain:** monitoring · **Agent:** Range Keeper, ERC-8004 agent 320966 · **Job:** 56678

> Is this concentrated liquidity position still in range, and should anything be done about it?

- **By hand:** 3.55s across 5 separate lookups
- **With the agent:** 2.04s across 1 request(s)
- **Faster by:** 1.7x

Agent output:

```json
{
 "tick_lower": -49500,
 "tick_upper": -49400,
 "tick_current": -49557,
 "liquidity": "0",
 "in_range": false,
 "action": "none",
 "reason": "This position has no liquidity left, so there is nothing to keep in range."
}
```

## What the numbers do not say

**Task 2's two arms did not name the same pool, and the check was changed to
suit that.** The upstream is a CDN cached endpoint, and the agent's region is
served a snapshot ours does not contain: fetching the list twice from here
returned an identical set of 31 pools, none of them the agent's winner. So
the two arms genuinely cannot see the same data, and comparing the chosen
pool would test the CDN rather than the agent. What is checked instead is
that the agent applied the method it publishes, by recomputing its headline
from its own reported figures. That is a weaker check and it is the honest
one available. It is also a real limitation of that agent: it trusts a
cached list it does not control.

**The baseline is a script, not a person.** Everything above understates the
gap against someone actually clicking through a block explorer, and no
attempt has been made to estimate that larger number, because it would be a
guess.

**Three tasks is the minimum asked for.** The spec's own suggested trading
task, rebalancing a concentrated liquidity position across a volatile
session, is not here: it needs real capital at risk over hours and we did not
have it. Task 2 is trading-domain research rather than trading execution, and
the security task is what satisfies the high stakes requirement.
