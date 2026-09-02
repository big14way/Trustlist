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

Section 2 was walked for real on 1 September 2026, and it found four things
that would have broken the recording. Each is now either fixed in the repo
or turned into a step below. Do not skip section 2.

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

Do these the day you record, in this order. Allow forty minutes, most of
it waiting on the job follower in step 2.2. If any step fails, stop and fix
it, because the script assumes all of them.

### 2.1 Bring the local stack up on mainnet, with a production web build

The hosted site serves a copy of the index through the API only; there is no
indexer running on Render. A hire made on camera will therefore not appear
on the hosted `/jobs` page. The local stack indexes HireRail live, so record
against it, and show the hosted site once at the end to prove it is public.

Two traps found on the walk through, both now handled by the order below:

- The release binaries in `target/release` can be older than the newest
  migration. A service started on a stale binary dies at once with
  "migration 13 was previously applied but is missing", and the only symptom
  on screen is a page that never updates. `make demo` rebuilds on macOS, so
  run it rather than restarting services by hand.
- A `next start` left running from an earlier day serves chunk names that no
  longer exist, so every script returns 400 and nothing hydrates: the
  counter does not animate, Hire does nothing, Verify never opens. Kill
  whatever is on port 3000 first, and record against a build made today.

```
cp web/.env.local.mainnet web/.env.local
pkill -f "next start"; pkill -f "next dev"
make demo
pkill -f "next dev"
cd web && NEXT_BUILD_DIR=.next-prod npx next build && \
  NEXT_BUILD_DIR=.next-prod nohup npx next start -p 3000 > /tmp/web.log 2>&1 &
```

The production build matters for a second reason: the dev server draws its
own indicator in the corner of every page, and it would be in every shot.

Then confirm, in a fresh browser window, that http://localhost:3000 shows a
real headline count, and that the count animates down. If it shows "the API
is not reachable", the API is not up; `tail /tmp/api.log`.

### 2.2 Make sure the job follower is at the head of the chain

`.env` must point the rail follower at an RPC that serves historical logs:

```
HIRE_RAIL=0x9fA9Cd8DDDd33eAc46C8c600371cc61ED79411e1
HIRE_RAIL_RPC=https://bsc.rpc.blxrbdn.com
HIRE_RAIL_CHAIN_ID=56
HIRE_RAIL_KERNEL=0xea4daa3100a767e86fded867729ae7446476eba6
HIRE_RAIL_DEPLOY_BLOCK=119125490
```

PublicNode refuses `eth_getLogs` from the deploy block as an archive
request, and the failure is silent from the outside: the jobs table simply
stays empty. That is what the walk through found, and it is why the value
above is not the RPC the rest of the stack uses.

The follower walks 2,000 blocks per pass, so from cold it needs about
twenty five minutes to reach the head. A hire made before it gets there will
not appear on `/jobs` until it does. Check with:

```
docker compose exec -T db psql -U trustlist -d trustlist -tAc \
  "select last_block from rail_state where chain_id = 56"
cast block-number --rpc-url https://bsc-rpc.publicnode.com
```

When the two numbers are within a few hundred blocks, open
http://localhost:3000/jobs with the deployer wallet connected and confirm
jobs 56675 to 56678 are listed as settled. Only then is the stack ready for
scene 5.

### 2.3 The wallet, and which agent to hire

The hire costs gas and a budget of 0.05 U. The deployer address
`0xFC4884Ee9553a7B412C923980c1cDD7dee82cB94` holds enough of both as of
1 September 2026: 0.2057 U and 0.0000972 BNB, against a full hire of about
0.0000375 BNB in gas. Its allowance to HireRail is zero, so the approve
prompt will appear on camera, which is what the script describes. Confirm
before recording:

```
cast balance 0xFC4884Ee9553a7B412C923980c1cDD7dee82cB94 --rpc-url https://bsc-rpc.publicnode.com
cast call 0xcE24439F2D9C6a2289F741120FE202248B666666 'balanceOf(address)(uint256)' 0xFC4884Ee9553a7B412C923980c1cDD7dee82cB94 --rpc-url https://bsc-rpc.publicnode.com
```

Import `DEPLOYER_KEY` into a fresh browser profile's MetaMask, on BNB Smart
Chain, and use that profile for the recording. Delete the imported account
from that profile afterwards.

Hire **Yield Scout, agent 320964**. It is ours, so we can sign the delivery
on camera, and the script says so out loud. It was chosen over Token Screen
because our three agents run on free Render instances that take 13 to 22
seconds to wake, against the prober's 8 second timeout, and on 1 September
Token Screen and Range Keeper both read as `down` while Yield Scout read as
`flaky` at 76 percent. Hiring an agent the site marks `down` would
contradict the pitch in the same shot. Check on the day and hire whichever
of the three is `live` or `flaky`:

```
for id in 320964 320966 322154; do curl -s localhost:8080/v1/agents/$id | python3 -c "import json,sys;a=json.load(sys.stdin);print(a['name'],a['status'],a['uptime_7d'])"; done
```

Wake all three a minute before recording so the delivery is fast:

```
for h in yield-scout range-keeper token-screen; do curl -s -m 60 -o /dev/null -w "$h %{http_code}\n" https://trustlist-$h.onrender.com/health; done
```

If a different agent is answering on the day, swap the two sentences that
name Yield Scout in scene 4 of the voice script; the rest stays true.

### 2.4 The numbers you will read

The voice script carries the numbers that are on screen in the recordings,
read from the local index at block 119,425,420. The registry moves, so before recording run this
and compare:

```
curl -s localhost:8080/v1/stats | python3 -m json.tool
curl -s localhost:8080/v1/agents/137
curl -s localhost:8080/v1/agents/137/reviews
```

| spoken in the script | field or source | value in the script |
|---|---|---|
| registered agents | `registered` | 327,046 |
| answer when probed | `live` plus `flaky` | 6,726 |
| share that answers | derived | 2.1 percent |
| declare an endpoint | `with_endpoints` | 83,806 |
| probes sent | `probes_total` | 4,631,331 |
| reviews on chain | `feedback` | 29,628 |
| distinct reviewing wallets | `reviewers` | 109 |
| independent reviewers | `reviewers_independent` | 31 |
| reviews that survive weighting | `reviews_kept` | 1,041, 3.5 percent |
| largest cluster | `largest_cluster_reviewers`, `largest_cluster_reviews` | 13 wallets, 13,103 reviews, 44 percent |
| agent 137 raw average | `/v1/agents/137/reviews` `raw_average` | 96.8 |
| agent 137 our score | `trust` | 90.4 |
| agent 137 reviews kept | `kept` of `total` | 10 of 25 |
| agent 137 probes and answer rate | `probes_7d`, `uptime_7d` | 567 probes, about 40 percent |
| advantage task 1 | `docs/ADVANTAGE_REPORT.md` | 58.52 seconds and 44 lookups by hand, 6.87 seconds and 4 requests with the agent, 8.5 times faster |
| advantage tasks 2 and 3 | same | 1.1 times and 1.7 times |
| first mainnet hire | `scripts/tx_log.md` | job 56675, 31 August 2026 |
| Merkle root coverage | `scripts/tx_log.md` | 40,004 agents |

If a value has drifted by more than rounding, change the words in section 4
to match what is on screen. A voice saying one number over a screen showing
another is the single easiest way to lose a judge. The README's own table is
dated to an earlier block and says so; it does not need to match the video.

### 2.5 Bring the hosted site up to date

Scene 9 shows trustlistapp.vercel.app. Its database is a copy, and on
1 September it was two days and five thousand agents behind the local index,
so its headline number would not have matched scene 1. Refresh it, and
allow twenty minutes:

```
bash scripts/sync_prod_db.sh
```

It measures before it truncates and refuses if the copy would not fit, so
read what it prints. `docs/HOSTING.md` explains the one time it was run
without that check.

### 2.6 Browser preparation

- Record at 1440p, browser at 100 percent zoom, window filling the screen.
- The collapse animation on the homepage runs once per browser session. Open
  a fresh window, or clear `sessionStorage`, immediately before the first
  take. If it does not animate, the shot is dead.
- Open these tabs in advance, in this order, so cuts are a keystroke:
  1. http://localhost:3000
  2. http://localhost:3000/stats
  3. http://localhost:3000/agents/137
  4. http://localhost:3000/agents/320964
  5. http://localhost:3000/jobs
  6. https://bscscan.com (leave on the search page)
  7. https://github.com/big14way/Trustlist/blob/main/docs/ADVANTAGE_REPORT.md
  8. http://localhost:3000/methodology
  9. https://trustlistapp.vercel.app
- Have a terminal open, font at 18 point or larger, in the repository root.
  It is on screen in scene 5. Before recording, export the provider key
  into it with a command that prints nothing, so the key is never on
  screen (this works in zsh and bash alike; `scripts/env.sh` is bash only):

  ```
  export PROVIDER_KEY=$(sed -n 's/^DEPLOYER_KEY=//p' .env)
  ```

  Then clear the terminal.

- Turn off notifications. Hide bookmarks. Close every other window.

### 2.7 What to record

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
| 4 | 1:05 to 1:35 | Agent 320964, Yield Scout. Press Hire. The sheet: spec, budget 0.05, "You release it" selected. MetaMask approve for exactly 0.05. MetaMask hire. The done state with the transaction hash. | Open `/agents/320964`. Click Hire. Set budget to 0.05. Leave mode on "You release it". Confirm. Approve in MetaMask, then sign the hire. Wait until the sheet shows the hash. Leave it on screen for two full seconds. |
| 5 | 1:35 to 2:00 | Split: terminal running `agent_deliver.sh`, then `/jobs` showing the job at "submitted", then "Accept and pay", then the panel reading "Settled". Then BscScan on the settle transaction. | In the terminal run `bash scripts/agent_deliver.sh <job id> "yield scout report" --yes`. Switch to `/jobs`, wait for the state to read SUBMITTED. Click "Accept and pay", sign. Wait for "Settled. The agent has been paid from escrow." Click "settle tx" and let BscScan load. Hold for three seconds. |
| 6 | 2:00 to 2:20 | Agent 137 again, the "Verify on chain" panel: "check this score", the two roots marked "(same)", then "these numbers are in the published snapshot" and "rejected, as it should be". | Open `/agents/137`. Click "check this score". It answers in about three seconds. Hold. |
| 7 | 2:20 to 2:40 | `docs/ADVANTAGE_REPORT.md` on GitHub: the results table, then the Cost table with the three job links. | Open the report. Scroll to Results. Wait. Scroll to Cost. Wait. |
| 8 | 2:40 to 2:52 | `/methodology`, scrolling from "Is the agent alive" through the reviewer weight table. | Open `/methodology`. Scroll slowly and steadily. |
| 9 | 2:52 to 3:05 | The hosted site at trustlistapp.vercel.app, then the repository README, then the homepage again for the last line. | Open the hosted site. Wait. Open the repo. Wait. Return to the homepage. Hold to the end. |

Scene 6 must use agent 137, not the agent you hired. Only scored agents are
in the published snapshot, and our own three are not scored, so the drawer
would answer "This agent is not in the latest snapshot" for them.

`agent_deliver.sh` reads the provider key from `PROVIDER_KEY`, which `.env`
does not define; the export in section 2.6 supplies it from the deployer,
which owns all three agents. Without it the script stops and asks, on
camera.

The job id for scene 5 is printed in the hire sheet's done state and on the
`/jobs` panel as "JOB 5xxxx". It is also the next number after 56678 unless
somebody else has hired through the rail since.

## 4. Voice script for VoiceBox

Paste this section, and only this section, into VoiceBox. It is about four
hundred and fifty words, which reads at a measured pace in a little over
three minutes. If the cut runs long, shorten scene 7 first.

Pronunciation notes, in case the voice needs them: "B N B" is three letters.
"E R C" is three letters. "Merkle" rhymes with "circle". "escrow" has the
stress on the first syllable. The stablecoin is called "U", the single
letter. "PancakeSwap" is one word.

---

Scene one.

B N B Smart Chain has three hundred and twenty seven thousand registered agents. Six thousand seven hundred of them answered when we called. That is two percent. The rest is a name and a wallet address.

Scene two.

We know, because we probe every declared endpoint every thirty minutes, and we keep the history. Four point six million probes so far. Eighty three thousand agents declare an endpoint at all. Nothing on this page comes from anyone else's dashboard.

The reviews are worse. Twenty nine thousand reviews on chain, written by one hundred and nine wallets. Only one thousand and forty one of those reviews, three and a half percent, survive our weighting. Thirteen of the wallets were funded from the same place, and between them they wrote forty four percent of every review on the registry. Thirty one reviewers, out of one hundred and nine, are independent.

Scene three.

Here is what that does to a single agent. Agent one hundred and thirty seven has a raw review average of ninety six point eight. Any marketplace ranking on reviews puts it near the top. We probed it five hundred and sixty seven times, and it answered about forty percent of them. When we drop the reviewers who cannot be shown to be independent, ten of its twenty five reviews survive. Our score is ninety point four, and its status is down.

We show both numbers, side by side, and every reviewer with the reason it was weighted. Nothing is deleted. It is weighted, and you can see the weight.

Scene four.

Then you can hire. This is Yield Scout, a read only PancakeSwap agent. It reads live pool data and reports which pools actually paid their liquidity providers, with a written reason. It holds no funds and signs nothing. It is our own agent, the only kind whose signing key we hold, and we say so rather than hide it.

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

## 5. The edit, in `video/`

The composition is a Remotion project in `video/`, and the cut is data.

```
cd video
npm install
bash prepare.sh        # cuts the Desktop recordings into public/clips
npm run render         # out/trustlist-demo.mp4, 2560 by 1440, 30 fps
```

`prepare.sh` expects the recordings on the Desktop under the names used on
the day (`homepage.mov`, `stats.mov`, `agent 137.mov`, `Yield Scout.mov`,
`split.mov`, `second agent 137 scene 6.mov`, `docs.mov`, `methodology.mov`,
`hosted site.mov`) and the VoiceBox files copied to `public/audio/scene1.wav`
to `scene9.wav`. Set `TRUSTLIST_RECORDINGS` to point somewhere else.

What the script does, and why:

- Crops the macOS menu bar and the browser chrome off using pixel positions
  measured from the frames (page content starts at y=228 in every clip), then
  takes a 16 by 9 box and scales it to 2560 by 1440. The split shot in scene
  5 keeps both the browser and the editor.
- The recordings are variable frame rate: macOS writes a frame only when the
  screen changes, so a segment over a still page holds a handful of frames.
  Every segment is padded from its last frame and capped at the exact length
  `src/timeline.ts` declares, so the timeline is always true.
- Scene 2's clip is shorter than its line, so its last frame holds. Scene 8
  scrolls at twice the recorded pace, which SPEC 24 allows; the MetaMask
  confirmations in scenes 4 and 5 are never sped up.

`src/timeline.ts` lists each scene's segments, voice file and overlays, with
the real transaction hashes for job 56686 read back from the chain. The
overlays use the site's own fonts and colours, and every hash stays on screen
for more than a second. Change a cut by editing the seconds there and in
`prepare.sh`, and rerun both.

Two things the first assembly taught:

- **Start the recording before the page loads.** The homepage counter runs
  once per browser session in the first second after load. A take that
  starts on a loaded page never shows it. Start the screen recording, then
  load `localhost:3000` in a new private window.
- **Record the hosted site only when the sync has finished.** A take made
  while `sync_prod_db.sh` was mid copy showed an empty marketplace.

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
