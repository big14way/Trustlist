# Demo video: script, shot list, and edit notes

Three minutes. Judges decide in the first twenty seconds, so the first shot
is the finding, not a logo.

Everything the voice says below is true of the product as it is today, and
every number is one our own instruments measured. Nothing in this script
mentions the Altana session flow, x402, or judge mode, because none of them
exist yet and SPEC rule 15 applies: underclaiming is survivable.

The voice track is generated with VoiceBox from the script in section 4.
That section is written to be read by a machine: every sentence ends in a
full stop, numbers are written as words, and abbreviations are spelled the
way they should sound. Do not paste the shot list into VoiceBox, only
section 4.

## 1. What the video has to prove

In order, because that is the order a judge will care:

1. The registry is mostly empty and the reviews are mostly one operator.
   We measured it ourselves.
2. The product shows the measurement honestly, next to the raw number.
3. A hire is a real ERC-8183 job on BNB Smart Chain mainnet, with escrow,
   and it completes on camera.
4. The scores are anchored on chain and a browser can check them.
5. The agent advantage was measured both ways and the agent did not win by
   a suspicious margin.
6. Every rule is published and the site is live.

## 2. Before you record

Do these the day you record, in this order. Steps 1 to 4 take about ten
minutes. If any of them fails, stop and fix it, because the script assumes
all of them.

### 2.1 Run the local stack against mainnet

The hosted site serves a copy of the index through the API only; there is no
indexer running on Render. A hire made on camera will therefore not appear
on the hosted `/jobs` page. The local stack indexes HireRail live, so record
against it, and show the hosted site once at the end to prove it is public.

```
cp web/.env.local.mainnet web/.env.local
make demo
```

`.env` must point `HIRE_RAIL` at `0x9fA9Cd8DDDd33eAc46C8c600371cc61ED79411e1`
with `HIRE_RAIL_CHAIN_ID=56`, which it already does. Open
http://localhost:3000 and confirm the headline count is a real number, not
"the API is not reachable".

### 2.2 The wallet for the hire

The hire costs gas and a budget of 0.05 U. The deployer address
`0xFC4884Ee9553a7B412C923980c1cDD7dee82cB94` holds enough of both as of
1 September 2026: 0.2057 U and 0.0000972 BNB, against a full hire of about
0.0000375 BNB in gas. Confirm before recording:

```
cast balance 0xFC4884Ee9553a7B412C923980c1cDD7dee82cB94 --rpc-url https://bsc-rpc.publicnode.com
cast call 0xcE24439F2D9C6a2289F741120FE202248B666666 'balanceOf(address)(uint256)' 0xFC4884Ee9553a7B412C923980c1cDD7dee82cB94 --rpc-url https://bsc-rpc.publicnode.com
```

Import `DEPLOYER_KEY` into a fresh browser profile's MetaMask, on BNB Smart
Chain, and use that profile for the recording. Delete the imported account
from that profile afterwards.

The agent to hire is Token Screen, agent 322154, because it is ours: it is
the only kind of agent whose owner key we hold, so we can sign the delivery
on camera. The script says so out loud. Hiding it would be worse than saying
it.

### 2.3 The numbers you will read

Every figure in the voice script comes from the README's table, read at
block 119,213,230 from the local index. The registry moves, so before
recording run this and compare:

```
curl -s localhost:8080/v1/stats | python3 -m json.tool
```

| spoken in the script | field or source | value in the script |
|---|---|---|
| registered agents | `registered` | 324,269 |
| answer when probed | `live` plus `flaky` | 7,782 |
| share that answers | derived | 2.4 percent |
| declare an endpoint | `with_endpoints` | 81,674 |
| probes sent | `probes_total` | 4,266,478 |
| reviews on chain | `feedback` | 29,626 |
| distinct reviewing wallets | `reviewers` | 108 |
| independent reviewers | `reviewers_independent` | 31 |
| largest cluster | `largest_cluster_reviewers`, `largest_cluster_reviews` | 13 wallets, 13,103 reviews, 44 percent |
| agent 137 raw average | `/v1/agents/137/reviews` `raw_average` | 96.8 |
| agent 137 our score | `trust` | 90.4 |
| agent 137 reviews kept | `kept` of `total` | 10 of 25 |
| agent 137 probes and answer rate | `probes_7d`, `uptime_7d` | 542 probes, under 38 percent |
| advantage task 1 | `docs/ADVANTAGE_REPORT.md` | 58.52 seconds and 44 lookups by hand, 6.87 seconds and 4 requests with the agent, 8.5 times faster |
| advantage tasks 2 and 3 | same | 1.1 times and 1.7 times |
| first mainnet hire | `scripts/tx_log.md` | job 56675, 31 August 2026 |
| Merkle root coverage | `scripts/tx_log.md` | 40,004 agents |

If a value has drifted by more than rounding, change the words in section 4
to match what is on screen. A voice saying one number over a screen showing
another is the single easiest way to lose a judge.

### 2.4 Browser preparation

- Record at 1440p, browser at 100 percent zoom, window filling the screen.
- The collapse animation on the homepage runs once per browser session. Open
  a fresh window, or clear `sessionStorage`, immediately before the first
  take. If it does not animate, the shot is dead.
- Open these tabs in advance, in this order, so cuts are a keystroke:
  1. http://localhost:3000
  2. http://localhost:3000/stats
  3. http://localhost:3000/agents/137
  4. http://localhost:3000/agents/322154
  5. http://localhost:3000/jobs
  6. https://bscscan.com (leave on the search page)
  7. https://github.com/big14way/Trustlist/blob/main/docs/ADVANTAGE_REPORT.md
  8. http://localhost:3000/methodology
  9. https://trustlistapp.vercel.app
- Have a terminal open, font at 18 point or larger, in the repository root,
  with `.env` loaded. It is on screen in scene 5.
- Turn off notifications. Hide bookmarks. Close every other window.

### 2.5 What to record

Record the screen once, as one continuous take if you can, following the
shot list in section 3. Do not narrate while recording. The voice track is
generated separately and laid over the cut in Remotion, so the screen
recording only has to hit each action in order with a pause of two or three
seconds between them. Long pauses are fine; they are cut out.

Also record, separately, thirty seconds of each of these so the edit has
spare footage: the homepage counter animating, the probe strip on agent 137,
the methodology page scrolling slowly, the BscScan page for the hire
transaction.

## 3. Shot list

Times are targets for the finished cut, not for the recording. The voice
line for each scene is in section 4 under the same scene number.

| scene | time | on screen | what you do while recording |
|---|---|---|---|
| 1 | 0:00 to 0:12 | Homepage. The counter collapses from the registered count to the answering count. | Load `/` in a fresh session. Do nothing for eight seconds. |
| 2 | 0:12 to 0:35 | `/stats`. The three big numbers under DOES ANYONE ANSWER, then the bar. Then IS THE PRAISE REAL. | Open `/stats`. Wait three seconds. Scroll slowly so the second section is fully visible. Wait. |
| 3 | 0:35 to 1:05 | Agent 137. The probe strip, then the REVIEWS panel with WHAT THE REGISTRY SAYS beside WHAT WE COUNT, then the expanded reviewer list. | Open `/agents/137`. Wait. Scroll to REVIEWS. Wait. Click "Show every reviewer and why we weighted it that way". Scroll slowly through five or six rows so the flags are readable. |
| 4 | 1:05 to 1:35 | Agent 322154, Token Screen. Press Hire. The sheet: spec, budget 0.05, "You release it" selected. MetaMask approve for exactly 0.05. MetaMask hire. The done state with the transaction hash. | Open `/agents/322154`. Click Hire. Set budget to 0.05. Leave mode on "You release it". Confirm. Approve in MetaMask, then sign the hire. Wait until the sheet shows the hash. Leave it on screen for two full seconds. |
| 5 | 1:35 to 2:00 | Split: terminal running `agent_deliver.sh`, then `/jobs` showing the job at "submitted", then "Accept and pay", then the panel reading "Settled". Then BscScan on the settle transaction. | In the terminal run `scripts/agent_deliver.sh <job id> "token screen report" --yes`. Switch to `/jobs`, wait for the state to read SUBMITTED. Click "Accept and pay", sign. Wait for "Settled. The agent has been paid from escrow." Click "settle tx" and let BscScan load. Hold for three seconds. |
| 6 | 2:00 to 2:20 | Back on agent 322154 or 137, the "Verify on chain" panel: "check this score", the two roots marked "(same)", and the honest and tampered results. | Open the agent page. Click "check this score". Wait for the result. Hold. |
| 7 | 2:20 to 2:40 | `docs/ADVANTAGE_REPORT.md` on GitHub: the results table, then the Cost table with the three job links. | Open the report. Scroll to Results. Wait. Scroll to Cost. Wait. |
| 8 | 2:40 to 2:52 | `/methodology`, scrolling from "Is the agent alive" through the reviewer weight table. | Open `/methodology`. Scroll slowly and steadily. |
| 9 | 2:52 to 3:05 | The hosted site at trustlistapp.vercel.app, then the repository README, then the homepage again for the last line. | Open the hosted site. Wait. Open the repo. Wait. Return to the homepage. Hold to the end. |

The job id for scene 5 is printed in the hire sheet's done state and on the
`/jobs` panel as "JOB 5xxxx". It is also the next number after 56678 unless
somebody else has hired through the rail since.

## 4. Voice script for VoiceBox

Paste this section, and only this section, into VoiceBox. It is about four
hundred and forty words, which reads at a measured pace in a little over
three minutes. If the cut runs long, shorten scene 7 first.

Pronunciation notes, in case the voice needs them: "B N B" is three letters.
"E R C" is three letters. "Merkle" rhymes with "circle". "escrow" has the
stress on the first syllable. The stablecoin is called "U", the single
letter.

---

Scene one.

B N B Smart Chain has three hundred and twenty four thousand registered agents. Seven thousand seven hundred and eighty two of them answered when we called. That is two point four percent. The rest is a name and a wallet address.

Scene two.

We know, because we probe every declared endpoint every thirty minutes, and we keep the history. Four point two million probes so far. Eighty one thousand agents declare an endpoint at all. Nothing on this page comes from anyone else's dashboard.

The reviews are worse. Twenty nine thousand reviews on chain, written by one hundred and eight wallets. Thirteen of those wallets were funded from the same place, and between them they wrote forty four percent of every review on the registry. Thirty one reviewers, out of one hundred and eight, are independent.

Scene three.

Here is what that does to a single agent. Agent one hundred and thirty seven has a raw review average of ninety six point eight. Any marketplace ranking on reviews puts it near the top. We probed it five hundred and forty two times, and it answered fewer than thirty eight percent of them. When we drop the reviewers who cannot be shown to be independent, ten of its twenty five reviews survive. Our score is ninety point four, and its status is down.

We show both numbers, side by side, and every reviewer with the reason it was weighted. Nothing is deleted. It is weighted, and you can see the weight.

Scene four.

Then you can hire. This is Token Screen, a security agent that reads a token contract and reports what its owner can still do to you. It is our own agent, the only kind whose signing key we hold, and we say so rather than hide it.

One budget, approved for exactly that amount, never an open allowance. One transaction opens, binds, and funds a real E R C eight one eight three job on mainnet. The money is in escrow. The agent has until the deadline to deliver, and if nothing arrives, every token comes back.

Scene five.

The agent delivers, signed by its owner. The job reads submitted. Nothing moves until the hirer decides. Accept, and the escrow releases to the agent in one transaction. There it is on B S C scan. Real job, real escrow, mainnet, a few seconds ago.

Scene six.

The scores are anchored on chain. We publish a Merkle root over forty thousand scored agents, and your browser asks the contract directly whether this agent's numbers are in it. It checks twice. Once with the real score, which passes. Once with the score inflated to perfect, which the contract rejects. You do not have to trust our A P I.

Scene seven.

We also measured whether an agent is worth hiring at all, three tasks, each run by hand and then through an agent paid from the same escrow. Screening four tokens for owner powers took fifty eight seconds and forty four lookups by hand, and under seven seconds with the agent. The other two tasks were nearly even, one point one and one point seven times faster. We publish the narrow wins too. A report where the agent wins three times over by a wide margin would not be believable.

Scene eight.

Every threshold is published. The probe cadence, the number of probes before a status is earned, each reviewer signal and its weight. The page is rendered from the same constants the scoring engine runs on, so the rules you read cannot drift from the rules that ran.

Scene nine.

The site is live, the code is public, and three contracts are verified on mainnet.

Anyone can list three hundred thousand agents. TrustList tells you which seven thousand are real, and shows you who paid for the praise.

---

## 5. Remotion notes

One composition, 2560 by 1440, 30 frames per second, about 5,550 frames.
Nine scenes, each a `<Sequence>` whose length matches the shot list.
Import the screen recording once and cut it with `startFrom` per scene
rather than exporting nine clips.

| scene | frames | overlay |
|---|---|---|
| 1 | 0 to 360 | none. Let the counter do the work. |
| 2 | 360 to 1050 | lower third at 2:00 into the scene: "13 wallets. 13,103 reviews. 44 percent." |
| 3 | 1050 to 1950 | two small labels when the panel is on screen: "what the registry says: 96.8" and "what we count: 90.4". Fade in with the voice. |
| 4 | 1950 to 2850 | when the hash appears, a lower third with the full hire transaction hash in a monospace face, held at least 30 frames after the voice finishes. |
| 5 | 2850 to 3600 | lower third with the settle transaction hash while BscScan is up. Same rule: at least a full second readable. |
| 6 | 3600 to 4200 | two labels: "real score: verified" and "inflated score: rejected". |
| 7 | 4200 to 4800 | lower third: "jobs 56676, 56677, 56678, mainnet". |
| 8 | 4800 to 5160 | none. |
| 9 | 5160 to 5550 | end card, last 90 frames: "trustlistapp.vercel.app" and "github.com/big14way/Trustlist". No logo animation. |

Rules for the edit, all from SPEC section 24:

- No intro, no logo, no stock music. If there is a bed at all, keep it
  under the voice by at least 20 dB and cut it entirely for scenes 4 and 5.
- Every transaction hash shown on screen stays readable for one full second
  minimum. The overlays exist because the sheet's own hash is small.
- Cuts land on the voice, not before it. Start each scene's footage two or
  three frames before the first word of its line.
- Do not speed up the MetaMask confirmations. The wait is the proof that
  a chain is involved.
- Do not add a caption saying "mainnet" anywhere it is not literally true.
  Scenes 4, 5, 6, and 7 are mainnet. Scene 2's numbers are from our own
  index of mainnet. That is all of them.

## 6. If the live hire cannot be recorded

If the deployer runs out of gas, or MetaMask misbehaves on the day, do not
fake it and do not record against the dev chain and call it mainnet.
Replace scenes 4 and 5 with:

- The `/jobs` page with the deployer connected, showing jobs 56675 to
  56678 as "Settled. The agent has been paid from escrow."
- BscScan on the accept transaction for job 56675:
  `0x240010b2c8440c784a3eadc1536a886196a81e65341ebbab5fad1ab89128abc1`

And change the scene five line to: "Four jobs have run this way on mainnet.
Here is the first, hired, delivered, accepted, and released from escrow on
the thirty first of August." Everything else in the script stays true.

## 7. After recording

- Put the finished video somewhere that survives the deployment dying:
  the repository release assets, and a second host. SPEC 30.7.
- Link it from `docs/SUBMISSION.md` and change the "Demo video" row from
  not done to done, with the URL.
- Delete the imported deployer account from the recording browser profile.
