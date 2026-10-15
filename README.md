# IMD RISK (RISK)

An immutable, fixed-supply ERC-20. The only production contract is
[`RiskToken`](src/RiskToken.sol), built on vendored OpenZeppelin Contracts v5.4.0.

| Parameter | Value |
| --- | --- |
| Solidity identifier | `RiskToken` |
| Fully qualified contract | `src/RiskToken.sol:RiskToken` |
| Name | `IMD RISK` |
| Symbol | `RISK` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Constructor transaction value | `0` |
| Initial recipient | Immediate deployer (`msg.sender`) |
| Assignment's launch chain | Robinhood Chain, chain ID `4663` |

## Behavior and assumptions

The constructor mints the entire supply exactly once and emits the standard
`Transfer(address(0), deployer, supply)` event. A direct deployment credits its
deployer; deployment through a factory credits that factory. The transaction
origin, requester, and any wallet funding the deployment receive nothing from
the constructor unless they are themselves the immediate deployer.

The requested behavior is interpreted as ordinary ERC-20 transfers and approvals.
Transfers deliver the exact requested amount. There are no taxes, transfer burns,
rebases, vesting, holding limits, or recipient callbacks. Zero-value transfers are
valid and emit `Transfer`. Transfers to the zero address and approvals to the zero
spender revert. Insufficient balances or allowances revert with OpenZeppelin's
ERC-6093 custom errors; failed operations roll back all state changes.

`approve` replaces the current allowance. `transferFrom` consumes finite
allowances; `type(uint256).max` represents an unlimited allowance and is not
decremented. Following OpenZeppelin v5, spending an allowance emits `Transfer`
without an additional `Approval` event. Indexers should query `allowance` when
they need its current value.

There is no owner, administrator, minter role, pause, blacklist, seizure, burn
entry point, proxy, initializer, or upgrade mechanism. The deployer has exactly
the same rights as any other holder after construction. No external function can
mint again or change metadata. Supply remains fixed even if a holder sends tokens
to an inaccessible address.

The token uses no external contracts, oracle, randomness, timestamps, block-number
logic, or chain-specific precompiles. No address or post-deployment configuration
is needed. The constructor makes no external calls and works on an empty chain.

## Build and checks

Run from the repository root with Foundry and Solidity `0.8.26` installed:

```sh
forge build
FOUNDRY_FUZZ_SEED=0xd23b2adc639ea766ecf715aa7e0ece75ad36233fd616eb44567a88744c59500d forge test
forge fmt --check
```

[`foundry.toml`](foundry.toml) pins Solidity `0.8.26`, the Cancun EVM target,
optimizer runs `200`, and `bytecode_hash = "none"`. The EVM target and optimizer
settings are explicit for reproducible deployment bytes. FFI and filesystem
permissions are not enabled. All Solidity dependencies and their licenses are
ordinary files under `lib/`; there are no submodules or installation steps.
Once the pinned compiler is available, `forge build --offline` and
`forge test --offline` need no network.

The delivered suite contains 34 tests:

- Metadata, supply, and the single mint event; direct and CREATE2 factory
  deployment; exact transfers, including full-balance, self, and zero transfers.
- Approval replacement and revocation, finite and infinite allowances, delegated
  transfers, and allowance isolation between callers.
- Failures for insufficient balance or allowance, invalid recipients/spenders,
  unauthorized spending, and native-currency payments; rollback checks verify
  that a rejected delegated transfer preserves its allowance and balances.
- Exact launch-style distribution and claim transfers, contract recipients that
  reject callbacks, rejected administrative selectors, and a scan for the
  protected checks' forbidden runtime opcodes.
- Four fuzz tests at 512 cases each and one stateful invariant at 128 runs of 64
  calls. The invariant checks balances and allowances against an independent
  accounting model and checks that all tracked balances sum to `10^27`.

Tests construct local fixtures and require no RPC, fork, wallet, or environment
configuration. The fuzz seed above controls reproducibility; tests themselves
do not read or set environment variables. Test fixture contracts exist only in
`test/` and are not application contracts to deploy.

## Deployment and operation

Deploy the creation bytecode for `src/RiskToken.sol:RiskToken`, with no appended
constructor arguments and no native currency. For review, obtain it with:

```sh
forge inspect src/RiskToken.sol:RiskToken bytecode
```

For the assignment's custom-token launch, the authorized launch factory must be
the immediate deployer so it receives the complete supply. The factory, rather
than the token, performs the prescribed 10% distributor transfer, 88% pool
allocation, and 2% remainder transfer. The external launch process supplies the
actual recipients, pool settings, and initial market-cap parameters. This token
contains no allocation wallets or exemptions and requires no initialization call.
The separate manifest step creates `launch.json` after acceptance.

The launch operator is responsible for selecting the chain and factory, using the
reviewed build settings, preparing the manifest, verifying the deployed source and
runtime, and checking the metadata, total supply, constructor mint event, and
factory's subsequent transfers. This repository does not broadcast transactions.

### After launch

There are no token setters, keeper jobs, oracle updates, role handovers, or owner
actions. Holders manage their own keys, recipients, and spender approvals. A
spender can use an allowance until it is consumed or revoked. Clients changing
an existing allowance should account for transaction ordering, for example by
confirming revocation before granting a replacement. Unlimited approvals give the
spender continuing access to the holder's balance.

Standard ERC-20 transfers do not check whether the recipient can later send
tokens back. Tokens sent to this token contract, or to another contract without
a suitable withdrawal method, cannot be recovered through `RiskToken`. Direct
native-currency payments revert; there is no rescue function for forced native
currency or other assets.

## Review scope

The local tests verify token behavior and launch-style ERC-20 transfer legs.
They do not simulate a real Uniswap pool, price discovery, liquidity accounting,
or a live-chain launch. The supplied protected harness depends on the launch
system's separate floor contracts and environment, which are not delivered here;
its full pool-seeding and swap checks belong to independent verification.

Local review covered supply reachability, administrative powers, external calls,
arithmetic and decimals, transfer failure atomicity, and dependency provenance.
The token has no external-call reentrancy surface or oracle/price dependency.
Foundry unit, fuzz, and invariant checks were run; Slither and Mythril were not
run. These checks are not an independent security audit. Independent review and
the launch system's acceptance checks remain release responsibilities.

