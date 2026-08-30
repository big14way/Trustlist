# Addresses

Every address TrustList touches, and what state it is in. `scripts/check_addresses.sh` reads this file back and calls BSC mainnet for each row, so a wrong or stale entry fails the gate rather than reaching a judge. Rows marked "not deployed" are checked in reverse: they must have no bytecode, so this document cannot go quietly out of date after a deploy.

All addresses are BSC mainnet, chain id 56, unless the row says otherwise.

## Ours

Nothing of ours is on mainnet yet. Both contracts are written, tested, and exercised end to end on a local dev chain, and `HireRailFork.t.sol` proves HireRail works against the real deployed ERC-8183 stack on a mainnet fork. Deployment is waiting on funding the deployer. The whole remaining plan costs 0.000246 BNB in gas at 0.05 gwei, itemised transaction by transaction in `docs/SUBMISSION.md` and measured in `docs/VERIFICATION.md` section 17.

| Contract | Address | State | Notes |
|---|---|---|---|
| HireRail | | not deployed | One transaction wraps create, fund, and set provider on the ERC-8183 kernel |
| TrustSnapshot | | not deployed | Publishes the Merkle root of every score |
| TrustListHook | | not deployed | Minimal IACPHook, satisfies the kernel's ERC-165 gate |
| Deployer | `0xFC4884Ee9553a7B412C923980c1cDD7dee82cB94` | not deployed | An externally owned account, so no bytecode is the correct state |

## ERC-8004, the registries we index

Verified 17 August 2026. Both are ERC-1967 UUPS proxies with Sourcify exact matches on their implementations. Details in `docs/VERIFICATION.md` section 2.

| Contract | Address | State | Notes |
|---|---|---|---|
| Identity Registry (proxy) | `0x8004A169FB4a3325136EB29fA0ceB6D2e539a432` | deployed | `AgentIdentity`, symbol AGENT. Not ERC721Enumerable, so the count lives in storage slot `0xa040f782729de4970518741823ec1276cbcd41a0c7493f62d173341566a04e00` |
| Identity Registry (implementation) | `0x7274e874CA62410a93Bd8bf61c69d8045E399c02` | deployed | `IdentityRegistryUpgradeable` |
| Reputation Registry (proxy) | `0x8004BAa17C55a88189AE136b182e5fdA19dE9b63` | deployed | Source of every feedback event we score |
| Reputation Registry (implementation) | `0x16e0FA7f7C56B9a767E34B192B51f921BE31dA34` | deployed | `ReputationRegistryUpgradeable` |

These are not deployed on BSC testnet. That is why judge mode runs on mainnet, per SPEC section 30.4.

## ERC-8183, the escrow we hire through

Verified 17 August 2026 against the BNBAgent SDK's own address registry.

| Contract | Address | State | Notes |
|---|---|---|---|
| AgenticCommerce kernel (proxy) | `0xea4daa3100a767e86fded867729ae7446476eba6` | deployed | ERC-1967 proxy |
| AgenticCommerce kernel (implementation) | `0xd5f9b570c96b5d67702d508c0bfb8b3b09209787` | deployed | |
| EvaluatorRouter | `0x51895229e12f9876011789b04f8698af06ccd6da` | deployed | Used in Protected mode |
| OptimisticPolicy | `0x9c01845705b3078aa2e8cff7520a6376fd766de5` | deployed | Seven day dispute window, immutable |
| Payment token, "United Stables" (U) | `0xcE24439F2D9C6a2289F741120FE202248B666666` | deployed | The kernel's settlement token |

## PancakeSwap, for our two reference agents

Verified 23 August 2026 by calling each one on BSC. Details in `docs/VERIFICATION.md` section 14.

| Contract | Address | State | Notes |
|---|---|---|---|
| NonfungiblePositionManager (V3) | `0x46A15B0b27311cedF172AB29E4f4766fbE7F4364` | deployed | Answers `name()` with "Pancake V3 Positions NFT-V1". The two other candidates in the docs are for other chains |
| PancakeV3Factory | `0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865` | deployed | Confirmed by resolving USDT/WBNB 0.05 percent to its pool |
| USDT/WBNB pool, 0.05 percent | `0x36696169C63e42cd08ce11f5deeBbCeBae652050` | deployed | The pool the factory resolves to |
| Infinity CLPositionManager | `0x55f4c8abA71A1e923edC303eb4fEfF14608cC226` | deployed | Not used yet, recorded because the track names Infinity |
| Infinity CLPoolManager | `0xa0FfB9c1CE1Fe56963B0321B32E7A0302114058b` | deployed | |
| Infinity Vault | `0x238a358808379702088667322f80aC48bAd5e6c4` | deployed | |

## Tokens

| Contract | Address | State | Notes |
|---|---|---|---|
| USDT (BSC) | `0x55d398326f99059fF775485246999027B3197955` | deployed | 18 decimals on BSC, not 6 |

## Local dev chain

Not listed here on purpose. Anvil addresses are deterministic and ephemeral, they are rewritten by `scripts/devchain.sh` on every run, and they live in `.devchain.env`. Putting them in a submission document would imply a permanence they do not have.
