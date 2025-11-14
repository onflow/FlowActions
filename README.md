# DeFiActions

**Composable DeFi primitives for building sophisticated financial workflows on Flow blockchain**

> :warning: This repo is in beta and not yet intended for use in production systems.

## Overview

DeFiActions provides a set of standardized interfaces that act as "money LEGOs" for the Flow ecosystem.

The framework abstracts away protocol-specific complexities, allowing developers to focus on building sophisticated DeFi strategies rather than wrestling with individual protocol integrations. Each component represents a fundamental financial operation that can be seamlessly connected with others.

Built natively for Flow's Cadence smart contract language, DeFiActions leverages Flow's unique capabilities including resource-oriented programming and upcoming features like scheduled callbacks to enable truly autonomous financial workflows.

## Status & Warnings

### Beta Software
DeFiActions is currently in **beta status** and undergoing active development. Interfaces may change based on community feedback and real-world usage patterns discovered during the FLIP review process.

### Interface Stability
- **No Backwards Compatibility Guarantee**: Interfaces may evolve significantly as the framework matures
- **Breaking Changes Expected**: Current implementations should be considered experimental 
- **Production Use Discouraged**: Not recommended for production-ready Mainnet deployments until interfaces stabilize
- **Community Feedback Welcome**: Developer input is actively sought to refine the interfaces before final release

### Recommended Approach
- **Experiment on Low Stakes Implementations**: Build and test integrations locally as much as possible and with minimal funds in pre-production contracts if on Mainnet
- **Stay Updated**: Monitor repository changes and FLIP discussions for interface updates
- **Provide Feedback**: Share implementation experiences to help shape the final interface design

## Deployments

| Contract | Testnet | Mainnet |
|----------|---------|---------|
| DeFiActions | 0x0b11b1848a8aa2c0 | 0x6d888f175c158410 |
| DeFiActionsUtils | 0x0b11b1848a8aa2c0 | 0x6d888f175c158410 |
| FungibleTokenConnectors | 0x4cd02f8de4122c84 | 0x0c237e1265caa7a3 |
| ERC4626Utils | 0x7014dcffa1f14186 | 0x04f5ae6bef48c1fc |
| ERC4626PriceOracles | 0x7014dcffa1f14186 | 0x04f5ae6bef48c1fc |
| ERC4626SinkConnectors | 0x7014dcffa1f14186 | 0x04f5ae6bef48c1fc |
| ERC4626SwapConnectors | 0x7014dcffa1f14186 | 0x04f5ae6bef48c1fc |
| EVMNativeFLOWConnectors | 0xbee3f3636cec263a | 0x1a771b21fcceadc2 |
| EVMTokenConnectors | 0xbee3f3636cec263a | 0x1a771b21fcceadc2 |
| SwapConnectors | 0xaddd594cf410166a | 0xe1a479f0cb911df9 |
| IncrementFiSwapConnectors | 0x494536c102537e1e | 0xe844c7cf7430a77c |
| IncrementFiFlashloanConnectors | 0x494536c102537e1e | 0xe844c7cf7430a77c |
| IncrementFiPoolLiquidityConnectors | 0x494536c102537e1e | 0xe844c7cf7430a77c |
| IncrementFiStakingConnectors | 0x494536c102537e1e | 0xe844c7cf7430a77c |
| BandOracleConnectors | 0xbb76ea2f8aad74a0 | 0xe36ef556b8b5d955 |
| UniswapV2Connectors | 0x5f1153f29b57747f | 0xf94f371678513b2b |

## Core Interfaces

DeFiActions defines five fundamental interface types that represent core DeFi operations:

### Primary Primitives

- **Source** - Provides tokens on demand (e.g., withdraw from vault, claim rewards)
- **Sink** - Accepts tokens up to capacity (e.g., deposit to vault, repay loan)  
- **Swapper** - Exchanges one token type for another (e.g., DEX trades, cross-chain swaps)
- **PriceOracle** - Provides price data for assets (e.g., external price feeds, DEX prices)
- **Flasher** - Issues flash loans with callback execution (e.g., arbitrage, liquidations)

### Advanced Components

- **AutoBalancer** - Automated rebalancing system that combines Sources, Sinks, and PriceOracles to maintain value equilibrium around the historical value of deposits & withdrawal
- **Quote** - Data structure for swap price estimates and execution parameters
- **ComponentInfo** - Metadata structure containing component type, identifier, and hierarchical information about inner components
- **UniqueIdentifier** - Traceability mechanism for identifying and tracking component operations across workflows

## Key Features

### Atomic Composition
All DeFiActions components execute within single transactions, ensuring that complex multi-step financial operations either complete entirely or fail safely without partial execution.

### Weak Guarantees Philosophy
Interfaces provide minimal behavioral promises, prioritizing flexibility and composability over strict guarantees. This allows for graceful handling of edge cases and enables robust workflows across diverse protocols, though it does put the responsibility of output validation on the consumer.

### Struct-Based Lightweight Design
Built using Cadence structs rather than resources, DeFiActions components are lightweight, easily copyable, and efficient and flexible to compose.

### Event-Driven Traceability
Comprehensive event emission enables full workflow tracing and debugging, with standardized events for deposits, withdrawals, swaps, flash loans, and component alignment operations.

## Quick Start

### Exploring the Codebase

To understand DeFiActions, start with these key files:

1. **[`cadence/contracts/interfaces/DeFiActions.cdc`](cadence/contracts/interfaces/DeFiActions.cdc)** - Core interface definitions and documentation
2. **[`cadence/contracts/connectors/FungibleTokenConnectors.cdc`](cadence/contracts/connectors/FungibleTokenConnectors.cdc)** - Basic Source/Sink implementations for FungibleToken vaults
3. **[`cadence/contracts/connectors/increment-fi/IncrementFiSwapConnectors.cdc`](cadence/contracts/connectors/increment-fi/IncrementFiSwapConnectors.cdc)** - Example protocol adapter for IncrementFi DEX integration

### Understanding the System

- **Start with the interfaces**: Review the core primitive definitions in `DeFiActions.cdc`
- **Study the connectors**: Examine `FungibleTokenConnectors.cdc` for basic implementation patterns
- **Explore protocol connectors**: See how external protocols integrate via the connector examples
- **Check the tests**: Browse `cadence/tests/` for usage patterns and workflow examples

## Development

### Prerequisites

- [Flow CLI](https://docs.onflow.org/flow-cli/install/) installed
- Basic understanding of [Cadence](https://cadence-lang.org/) smart contract language

### Setup

1. **Install dependencies**
   ```sh
   flow deps install
   ```

2. **Run tests**
   ```sh
   make test
   ```

3. **Run specific test suites**
   ```sh
   # Test core functionality
   flow test cadence/tests/DeFiActions_test.cdc
   
   # Test FungibleToken connectors
   flow test cadence/tests/FungibleTokenConnectors_test.cdc
   
   # Test protocol connectors
   flow test cadence/tests/IncrementFiSwapConnectors_test.cdc
   ```

### Local Development

- **Flow configuration**: See [`flow.json`](flow.json) for network and contract configurations
- **Test accounts**: Tests use temporary accounts created during test execution
- **Mock contracts**: Test implementations available in [`cadence/tests/contracts/`](cadence/tests/contracts/)

## Examples

### Connector Implementations

**Basic Vault Operations:**
- [`VaultSink`](cadence/contracts/connectors/FungibleTokenConnectors.cdc) - Deposits tokens to a FungibleToken vault with capacity limits
- [`VaultSource`](cadence/contracts/connectors/FungibleTokenConnectors.cdc) - Withdraws tokens from a FungibleToken vault with minimum balance protection
- [`VaultSinkAndSource`](cadence/contracts/connectors/FungibleTokenConnectors.cdc) - Combined deposit/withdrawal functionality for a single vault

**Protocol Connectors:**
- [`IncrementFiSwapper`](cadence/contracts/connectors/increment-fi/IncrementFiSwapConnectors.cdc) - DEX integration for token swapping via IncrementFi
- [`BandPriceOracle`](cadence/contracts/connectors/bande-oracle/BandOracleConnectors.cdc) - Price feed integration with Band Protocol oracle
- [`EVMSwapperV2`](cadence/contracts/connectors/evm/UniswapV2SwapConnectors.cdc) - UniswapV2-style swapping on Flow EVM
- [`EVMSwapperV3`](cadence/contracts/connectors/evm/UniswapV3SwapConnectors.cdc) - UniswapV3-style swapping on Flow EVM

### Usage Patterns

Additional usage patterns will be linked here once they become available.

## Documentation

- **FLIP Document**: DeFiActions FLIP - TBD
