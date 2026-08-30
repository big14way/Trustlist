# Zero dead ends

SPEC.md Section 30.5 lists eighteen states that must never leave a visitor
stuck, and says to walk them by hand before submission. This is that walk,
done on 30 August 2026 against the running app.

Nine of the rows are checked by `web/e2e/deadends.spec.ts` so they stay
checked rather than being true once. The rest were walked by hand, and the
method is written next to each one, because "we looked at it" is not a
result anyone can repeat.

Seven rows failed the first time. What was wrong and what fixed it is below
the table.

| State | Result | How it was checked |
|---|---|---|
| No wallet extension installed | pass | Read `HireSheet`: with no injected connector the sheet explains and links to bnbchain.org/en/wallets, and every page stays browsable |
| Wrong network | pass | Inline "Switch to BNB Smart Chain" button on the confirm row, no modal wall |
| Zero BNB for gas | **fixed** | Was unhandled. Now checked before the button is live |
| Insufficient token balance | pass | Shows required against held and disables confirm, so the chain never sees it |
| Allowance too low | pass | One extra labelled step inside the same flow: "Approve and hire for 1 U" |
| User rejects the transaction | pass | Returns to the form with the spec, budget and deadline intact, and says nothing was sent |
| Transaction stuck pending | pass | Renders the hash with a BscScan link as soon as it is sent, never a spinner alone |
| Page refreshed mid flow | **fixed** | The intent was written and never read back |
| Back button mid flow | pass | Reopening the sheet restores the pending hash rather than starting a second hire |
| API down | **fixed** | Two pages said the wrong thing |
| RPC down | **fixed** | There was no failover to fail over to |
| Agent endpoint dies mid job | pass | Job panel names the deadline in UTC and says the escrow can be reclaimed |
| Agent submits nothing before deadline | pass | Reclaim appears on its own, on the chain's clock, not the browser's |
| Zero search results | **fixed** | Was a sentence with nothing to click |
| 360px mobile | pass | Automated: every page measured for horizontal overflow at 360px |
| Slow connection | **fixed** | No skeleton existed |
| Screen reader | pass | Automated: the probe strip carries a sentence, every status pill carries a word |
| Missing page or unknown agent id | **fixed** | Was Next's default 404: the number on a blank screen |

## What was broken

### The refresh recovery was decoration

`HireSheet` wrote the hire intent to `localStorage` before sending, with a
comment saying a refresh could recover it. Nothing ever read it back. A
visitor who refreshed between signing and confirmation had a transaction in
flight and no way to find it from our UI, which is the exact dead end the
section is about.

It now reads the intent on mount, restores the hash and the spec, and clears
the entry once the chain answers. Only intents under an hour old are
restored; anything older is a hash the reader has long since watched resolve.

### Nothing checked whether you could pay for gas

The checkout read the payment token balance and the allowance, and never
looked at native BNB. A wallet holding plenty of U and no BNB could fill in
the whole form and press the button, and the failure arrived as an opaque
wallet error.

It now reads the native balance and says so before the button is live: "This
wallet holds no BNB, so it cannot pay the gas for any transaction, whatever
its U balance."

### Two pages blamed our data for someone else's outage

`/stats` said "Nothing has been measured yet, so there is nothing to report"
whether the prober had genuinely measured nothing or our API was simply
unreachable. Those look identical on screen and are not the same claim.

Worse, the agent page called `notFound()` whenever the API returned nothing,
so during an outage a real agent got "There is nothing at this address". The
registry does not stop having agent 1 because our API is down.

`apiGetResult` now distinguishes a 404 from an unreachable API, and both
pages say which one happened. The agent page also links out to 8004scan so
the reader can answer the question we cannot.

### There was no RPC failover in the browser

`docs/VERIFICATION.md` section 10 compares BSC endpoints and the backend uses
two. The browser used viem's single built in endpoint for BSC, so one bad
minute at one provider broke every read in the wallet path with nothing
behind it. It now uses a viem `fallback` across two endpoints, which ranks by
health and moves on by itself.

### The empty state had nothing to click

Section 18.5 asks for an action, not an apology. Filtering to a category with
nothing answering produced one sentence and no way forward. It now offers
"Show every category", "Show the 72,771 that do not answer" with the real
count, and a link to what we have measured.

### There was no skeleton

The marketplace is server rendered on every request because its numbers
change whenever the prober runs, so a slow connection got a blank screen.
There is now a skeleton with the marketplace's own layout, so nothing moves
when the real page arrives.

It is scoped to the marketplace with a route group, and that detail matters.
Placing it at the app root instead put every route behind a streamed shell,
and a streamed response cannot set a status code after the fact: it silently
turned the 404 on a missing agent into a 200. Caught by the status assertions
in the spec file.

### A missing page was a blank wall

`/nosuchpage` and `/agents/999999999` both rendered Next's default 404: the
number 404, no explanation, no navigation. There is now a `not-found.tsx`
that says what happened and offers three ways on, and an `error.tsx` for a
render that throws, which retries in place rather than reloading and states
plainly that no transaction was sent.

## Two deliberate deviations

**"API down: cached data still renders."** We do not do this and we are not
going to. Serving a remembered number during an outage means showing a figure
we cannot re-derive, which is the one thing the whole product argues against.
The banner names the outage instead and the page shows nothing rather than
something stale. This is the more honest failure and it is a real deviation
from the spec text.

**"Zero BNB for gas: links to the faucet in judge mode."** Judge mode does
not exist yet, so there is no faucet to link. The state is named clearly and
says roughly what a hire costs, which is the part that helps. The link
follows judge mode if judge mode gets built.

## What is still only checked by hand

These need a wallet, a live outage, or a stuck transaction, so they are not
in the automated file. Each was walked once, on the date above, by reading
the code path and exercising it where possible:

- wallet absent, wrong network, rejected signature, stuck pending
- refresh and back button mid flow
- RPC failover, which was verified by configuration rather than by taking a
  provider down

The API down row was exercised for real, by building the app against a dead
API address and requesting every page.
