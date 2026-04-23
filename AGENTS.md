# AGENTS.md

Guidance for AI coding agents (Claude Code, Codex, Cursor, Copilot, Gemini CLI) working in
this repository. Loaded into agent context automatically — keep it concise.

## Overview

DeFiActions is a Cadence framework of composable "money LEGO" primitives (Source, Sink,
Swapper, PriceOracle, Flasher, AutoBalancer) for building DeFi workflows on Flow. Core
interfaces live in `cadence/contracts/interfaces/DeFiActions.cdc`; protocol adapters live
under `cadence/contracts/connectors/`. The repo also contains a Foundry-managed Solidity
side under `solidity/` for EVM-side contracts used by the EVM connectors. Status: beta —
README explicitly warns "not yet intended for use in production systems."

## Build and Test Commands

All Cadence commands are driven by the `Makefile`:

- `make test` — run the full Cadence test suite with coverage
  (`flow test --cover --covercode="contracts" --coverprofile="coverage.lcov" ./cadence/tests/*_test.cdc`)
- `make lint` — run `flow cadence lint` over every `cadence/contracts/**/*.cdc`
- `make ci` — `lint` + `test` (the job run by `.github/workflows/cadence_tests.yml`)
- `flow deps install --skip-alias --skip-deployments` — install Flow dependencies
  (matches CI step; plain `flow deps install` is shown in README)
- `flow test cadence/tests/<Specific>_test.cdc` — run one suite

Solidity side (Foundry, configured via `foundry.toml`):

- `forge fmt --check` — format check (CI gate, `.github/workflows/test.yml`)
- `forge build --sizes --via-ir --optimize` — build (CI gate)
- Sources in `solidity/src/`, tests in `solidity/test/`, libs in `solidity/lib/`
  (git submodules: forge-std, flow-sol-utils, openzeppelin-contracts, aave-v3-core,
  v2-core, v2-periphery, More-Vaults — see `.gitmodules`)

CI uses Flow CLI `v2.15.3` and Go `1.23.x` (`.github/workflows/cadence_tests.yml`).

## Architecture

```
cadence/
  contracts/
    interfaces/DeFiActions.cdc      # All core interfaces + AutoBalancer resource
    utils/                          # DeFiActionsUtils, ERC4626Utils, EVMAbiHelpers
    connectors/
      FungibleTokenConnectors.cdc   # VaultSink, VaultSource, VaultSinkAndSource
      SwapConnectors.cdc            # MultiSwapper, SwapSource, SwapSink, SequentialSwapper
      band-oracle/                  # BandOracleConnectors.cdc
      increment-fi/                 # Swap, Staking, PoolLiquidity, Flashloan connectors
      evm/                          # UniswapV2/V3, ERC4626 (PriceOracle/Sink/Swap),
                                    # EVMNativeFLOW, EVMToken, EVMAmountUtils
      evm/morpho/                   # MorphoERC4626 Sink + Swap connectors
  tests/                            # *_test.cdc suites, fork/ (mainnet-fork tests),
                                    # contracts/ (mocks: MockOracle, MockSwapper,
                                    # TokenA/B/C, TestTokenMinter, ExecutionCallbackRecorder)
  transactions/                     # Per-connector tx scripts (12 subfolders)
  scripts/                          # Read-only query scripts per connector family
solidity/
  src/  test/  lib/                 # Foundry layout (per foundry.toml)
```

### Core interfaces (verified in `cadence/contracts/interfaces/DeFiActions.cdc`)

| Name | Kind | Line |
|---|---|---|
| `Sink` | `struct interface` | 267 |
| `Source` | `struct interface` | 299 |
| `Swapper` | `struct interface` | 345 |
| `PriceOracle` | `struct interface` | 430 |
| `Flasher` | `struct interface` | 449 |
| `Quote` | `struct interface` | 329 |
| `UniqueIdentifier` | `struct` | 130 |
| `ComponentInfo` | `struct` | 151 |
| `AutoBalancer` | **`resource`** | 708 |

The framework is primarily struct-based for lightweight composition, **except
`AutoBalancer`**, which is a resource (conforms to `FungibleToken.Receiver`/`Provider`,
`ViewResolver.Resolver`, `Burner.Burnable`, `FlowTransactionScheduler.TransactionHandler`).
Do not claim "everything is a struct."

## Conventions and Gotchas

- **AutoBalancer is a resource, not a struct.** It wraps an inner `@{FungibleToken.Vault}?`
  and must be destroyed via `Burner.burn()` so the inner vault's `burnCallback()` runs
  (see field comments around line 725–727).
- **Weak guarantees.** Source/Sink/Swapper interfaces intentionally promise very little;
  output validation is the caller's responsibility (README "Weak Guarantees Philosophy").
- **`testing` alias is `0x0000000000000009`** for every DeFiActions contract in `flow.json`
  except `BandOracleConnectors` and `SwapConnectors` (both `0x0000000000000007`) and the
  test token contracts `TokenA/B/C` + `TestTokenMinter` (`0x0000000000000010`).
- **Deployed addresses live in `flow.json` aliases**, not in code. Verified mainnet/testnet
  pairs (partial list):
  - `DeFiActions` / `DeFiActionsUtils` — mainnet `0x6d888f175c158410`, testnet `0x0b11b1848a8aa2c0`
  - `FungibleTokenConnectors` — mainnet `0x0c237e1265caa7a3`, testnet `0x4cd02f8de4122c84`
  - `SwapConnectors` — mainnet `0xe1a479f0cb911df9`, testnet `0xad228f1c13a97ec1`
  - `BandOracleConnectors` — mainnet `0xe36ef556b8b5d955`, testnet `0xbb76ea2f8aad74a0`
  - `EVMNativeFLOWConnectors` / `EVMTokenConnectors` — mainnet `0x1a771b21fcceadc2`,
    testnet `0xbee3f3636cec263a`
  - IncrementFi connectors have `testing` aliases only — no mainnet/testnet in `flow.json`
    (README lists mainnet/testnet addresses `0xe844c7cf7430a77c` / `0x494536c102537e1e`
    which are not mirrored into `flow.json`; treat the README as the source for those).
- **`mainnet-fork` network** is defined in `flow.json` (host `127.0.0.1:3569`, fork
  `mainnet`). Fork-only tests live in `cadence/tests/fork/`.
- **Coverage output** lands at `coverage.lcov` at repo root (Makefile `test` target).
- **Lint gate** (`make lint`) greps for `"Lint passed"` in `flow cadence lint` output —
  a lint warning fails CI.
- **`emulator-account.pkey` is committed** intentionally (test key, not a real credential).
- **Solidity submodules must be initialized** (`git submodule update --init --recursive`)
  before `forge build` — CI uses `submodules: recursive` on checkout.

## Files Not to Modify

- `solidity/lib/**` — git submodules (forge-std, openzeppelin-contracts, aave-v3-core,
  v2-core, v2-periphery, flow-sol-utils, More-Vaults)
- `emulator-account.pkey` — emulator test key, required as-is by `flow.json`
- `coverage.lcov` — generated by `make test`
- `foundry.lock` — Foundry lockfile
