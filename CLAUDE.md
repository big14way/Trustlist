# Rules for the coding agent

1. Read `SPEC.md` before every significant task. When something in the code contradicts the spec, ask, do not silently pick.
2. No em dashes, no en dashes, anywhere. Code comments, commit messages, UI copy, docs, all of it.
3. Never fabricate a contract address, an ABI, an endpoint, a package version, or a statistic. Verify against the live source or say you could not.
4. No mock data after Milestone 1. If a screen has nothing to show, build the empty state instead of faking rows.
5. Money is `rust_decimal` or `BigInt`. Never `f64`, never JavaScript `number`, for token amounts.
6. Every external call gets a timeout. Every loop over agents gets a rate limit. Every user input that becomes a URL gets the SSRF guard.
7. Never request an unbounded token allowance. Exact amounts only.
8. Private keys come from the environment and are used only in scripts, never in `api`, never in `web`.
9. Prefer boring, readable code over clever code. A judge may read this repo.
10. Commit at every working state with a plain message describing what changed. Small commits.
11. When you finish a milestone, stop and report: what works, what does not, what you had to change from the spec and why.
12. If you are stuck for more than two attempts on the same error, stop and ask rather than rewriting the architecture around the problem.
13. Do not add dependencies without saying why. Do not add a UI component library.
14. Do not ship a token, a points system, or an airdrop.
15. When in doubt about a claim shown to a user, weaken the claim. Underclaiming is survivable, overclaiming in front of judges is not.

House rules for every file written here, including comments, commit messages, and UI copy:

- No em dashes and no en dashes anywhere. Use commas, colons, parentheses, or a new sentence.
- Plain human prose. No "delve", no "leverage" as a verb, no "in the ever evolving landscape of".
- Never invent a contract address, an API endpoint, a package name, or a version number. If not certain, verify against the live source, and if it cannot be verified, say so in the output.
- Every number shown in the UI must trace back to something read from chain or measured by our own prober. No mock data past Milestone 1.

Commit rule for this repo: commit and push to https://github.com/big14way/Trustlist.git after each milestone, without a co-authored line in the commit message.
