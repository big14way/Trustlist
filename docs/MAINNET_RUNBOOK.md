# Mainnet runbook

What to run, in what order, to take TrustList from nothing on mainnet to a
completed hire you can demo from the browser.

Every step here has been rehearsed against a fork of BSC mainnet with
`scripts/mainnet_rehearsal.sh`, which uses the real ERC-8004 registry, the
real ERC-8183 kernel, the real PancakeSwap router and the real payment token.
The gas numbers below come from that run, not from estimates.

Rehearsed 30 August 2026 at block 118,978,591.

## Before you start

**A BscScan API key.** `BSCSCAN_API_KEY` is empty. Without it `--verify` has
nothing to authenticate with and the contracts deploy unverified, which is
recoverable with `forge verify-contract` but is one more thing to do later.
`contracts/foundry.toml` has the etherscan section ready and reads the key
from the environment.

**One funded account.** Everything below can be done by a single address.
`DEPLOYER_KEY` in `.env` derives to
`0xFC4884Ee9553a7B412C923980c1cDD7dee82cB94`, the address in
`docs/ADDRESSES.md`. Import that key into a browser wallet and you can also
use it as the hirer in the UI, which keeps the whole story on one address and
strands no BNB in a second wallet.

You can split the roles across two addresses if you would rather the demo
show two distinct parties. The agent owner needs only enough BNB to sign one
`submit`, which is 93,412 gas.

**A public https home for the agent.** The registry stores a URL, and our own
prober fetches it. A card URL that is not reachable makes the agent index
without a name and score as dormant, which is the opposite of a demo. The
agent already serves a valid ERC-8004 card at
`/.well-known/agent-card.json`; it just needs somewhere to live:

```
python3 agents/pancake-yield/server.py --port 8081
```

The URL is not permanent. `setAgentURI` can repoint it later for one
transaction, so a host you might change is not a trap.

## What it costs

| step | gas | measured by |
|---|---|---|
| deploy TrustListHook | 189,252 | forge script, mainnet estimate |
| deploy HireRail | 2,520,666 | forge script, mainnet estimate |
| deploy TrustSnapshot | 1,177,953 | forge script, mainnet estimate |
| publish the first root | 224,788 | forge script, mainnet estimate |
| register the agent | 180,164 | fork rehearsal, actual gas used |
| swap 0.002 BNB into U | 144,785 | `cast estimate`, live mainnet |
| approve U | 60,245 | fork rehearsal, actual gas used |
| `hire` | 471,090 | fork rehearsal, actual gas used |
| `submit` | 93,412 | fork rehearsal, actual gas used |
| `accept` | 118,108 | fork rehearsal, actual gas used |

One end to end hire is 742,855 gas, which is 0.0000371 BNB at the 0.05 gwei
BSC is charging. Deploying everything and running the hire three times comes
to 6,666,173 gas, or 0.00033 BNB.

The only real money is the job budget. 0.002 BNB buys about 1.39 U, and the
rehearsal confirms the provider is paid in full with no fee taken, so if you
hire your own agent the U comes straight back and one purchase covers every
run.

Fund with **0.01 BNB**. That is thirty times the gas, and the margin is for
the Altana session grant and revoke, which are not in the table because the
relay charges in native BNB and we have never completed a grant.

## Rehearse first

```
bash scripts/mainnet_rehearsal.sh
```

It forks mainnet, funds two accounts on the fork, and runs the whole sequence
including the scripts below. It ends with `REHEARSAL PASSED` and a gas table.
Nothing touches mainnet. Run this after any change to the contracts or the
scripts.

## The run

### 1. Deploy

```
cd contracts
DEPLOYER_KEY=$DEPLOYER_KEY forge script script/Deploy.s.sol:Deploy \
  --rpc-url $BSC_RPC_HTTP --broadcast --verify
```

Record `HireRail` and `TrustListHook` in `docs/ADDRESSES.md`, changing their
state from `not deployed` to `deployed`. `scripts/check_addresses.sh` asserts
that rows marked `not deployed` have no bytecode, so the gate fails until the
document is updated. That is deliberate.

Then set in `.env`:

```
HIRE_RAIL=<address>
HIRE_RAIL_RPC=$BSC_RPC_HTTP
HIRE_RAIL_KERNEL=0xea4daa3100a767e86fded867729ae7446476eba6
HIRE_RAIL_DEPLOY_BLOCK=<deploy block>
NEXT_PUBLIC_HIRE_RAIL=<address>
NEXT_PUBLIC_PAYMENT_TOKEN=0xcE24439F2D9C6a2289F741120FE202248B666666
NEXT_PUBLIC_CHAIN_ID=56
```

### 2. Publish a snapshot root

The first time, and only the first time:

```
bash scripts/publish_snapshot.sh --deploy-register
```

Every time after that, with `TRUST_SNAPSHOT` set in `.env`:

```
bash scripts/publish_snapshot.sh
```

Do not use `scripts/ci_snapshot.sh` here. That one is built for CI: it starts
anvil and deploys a fresh register on every run, which on mainnet would leave
two registers and orphan every proof already published against the first.
`publish_snapshot.sh` refuses to deploy a second register, refuses to publish
a root that is already recorded as published, checks that the signer is a
publisher before spending gas, and prints the cost before asking.

Set `TRUST_SNAPSHOT` and `NEXT_PUBLIC_TRUST_SNAPSHOT` afterwards, together
with `NEXT_PUBLIC_CHAIN_ID`. The verify drawer reads the address and the
chain id as a pair, so setting one without the other points a reader's wallet
at the wrong chain and shows a verification that cannot be true.

### 3. Register the agent

With the agent serving its card on a public https URL:

```
bash scripts/register_agent.sh https://<your host>/.well-known/agent-card.json
```

It fetches and validates the card before signing: JSON, a name, and at least
one absolute http endpoint, which is exactly what `crates/prober/src/card.rs`
looks for. It prints the cost and asks before sending. It writes the
transaction to `scripts/tx_log.md`.

Note the agent id it prints. Our indexer will pick the agent up on its next
pass; until then it is not in the marketplace.

### 4. Buy the job budget

```
cast send 0x10ED43C718714eb63d5aA57B78B54704E256024E \
  'swapExactETHForTokens(uint256,address[],address,uint256)' \
  0 "[0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c,0xcE24439F2D9C6a2289F741120FE202248B666666]" \
  <your address> $(( $(date +%s) + 600 )) \
  --value 2000000000000000 --private-key $DEPLOYER_KEY --rpc-url $BSC_RPC_HTTP
```

### 5. Hire from the UI

Connect the wallet, open the agent, hire it in Direct mode. The app signs
`approve` for the exact budget and then `hire`. Both land on BscScan under
HireRail, which is the pair of mainnet transactions the spec asks for.

### 6. Deliver as the agent

The web app cannot do this, because submitting is the agent's side of the
deal. On a dev chain the e2e suite impersonates the provider, which mainnet
does not allow, so the owner signs for real:

```
PROVIDER_KEY=$DEPLOYER_KEY bash scripts/agent_deliver.sh <job id> \
  "three pools ranked, reasoning attached"
```

It refuses early and clearly if the signer is not the job's provider, if the
job is not in `Funded`, or if the deadline has passed.

### 7. Accept

Back in the job panel, Accept releases the escrow to the provider in the same
block. The rehearsal asserts the provider is paid in full and the rail is
left holding nothing.

## After the run

- Verify all three contracts on BscScan, either with `--verify` at deploy
  time or `forge verify-contract` afterwards.
- Update `docs/ADDRESSES.md` with the real addresses.
- Paste the hashes from `scripts/tx_log.md` into `docs/SUBMISSION.md`.
- Re-run `make verify`. The address checker will now confirm the contracts
  exist rather than confirming they do not.

## If something goes wrong

**The card URL was wrong.** `cast send $IDENTITY_REGISTRY
'setAgentURI(uint256,string)' <agent id> <new url>`. One transaction.

**The job was never delivered.** After the deadline, `reclaim` on the job
panel returns the escrow to the hirer. Journey 04 covers this path.

**The hire reverted with `DeadlineTooSoon`.** Direct jobs need at least five
minutes of lead. Protected jobs need to outlast the live seven day dispute
window, and the app already forces that.
