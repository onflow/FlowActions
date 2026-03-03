import "FungibleToken"
import "EVM"
import "FlowEVMBridgeConfig"

import "DeFiActions"
import "UniswapV3SwapConnectors"

/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
/// THIS CONTRACT IS IN BETA AND IS NOT FINALIZED - INTERFACES MAY CHANGE AND/OR PENDING CHANGES MAY REQUIRE REDEPLOYMENT
/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
///
/// UniswapV3SwapperProvider
///
/// DeFiActions SwapperProvider implementation for Uniswap V3 on Flow EVM.
/// Pre-computes and stores all swappers at initialization for O(1) lookup during liquidations.
/// Supports both direct swaps and multi-hop routes through intermediate tokens.
///
access(all) contract UniswapV3SwapperProvider {

    /// TokenConfig
    ///
    /// Configuration for a token supported by the provider.
    /// Links a Cadence FungibleToken.Vault type to its corresponding ERC20 address on Flow EVM.
    ///
    access(all) struct TokenConfig {
        access(all) let flowType: Type           // Cadence type, e.g., Type<@FlowToken.Vault>()
        access(all) let evmAddress: EVM.EVMAddress  // Corresponding ERC20 address

        init(flowType: Type, evmAddress: EVM.EVMAddress) {
            pre {
                flowType.isSubtype(of: Type<@{FungibleToken.Vault}>()):
                    "flowType must be a FungibleToken.Vault"
                FlowEVMBridgeConfig.getTypeAssociated(with: evmAddress) == flowType:
                    "flowType must be associated with evmAddress in FlowEVMBridgeConfig"
            }
            self.flowType = flowType
            self.evmAddress = evmAddress
        }
    }

    /// RouteConfig
    ///
    /// Configuration for a trading route between two tokens.
    /// Supports multi-hop paths through intermediate tokens.
    ///
    access(all) struct RouteConfig {
        access(all) let inToken: Type
        access(all) let outToken: Type
        access(all) let tokenPath: [EVM.EVMAddress]  // Multi-hop path support
        access(all) let feePath: [UInt32]             // Fee tiers in basis points (500, 3000, 10000)

        init(inToken: Type, outToken: Type, tokenPath: [EVM.EVMAddress], feePath: [UInt32]) {
            pre {
                tokenPath.length >= 2: "tokenPath must have at least 2 tokens"
                feePath.length == tokenPath.length - 1: "feePath length must be tokenPath.length - 1"
                inToken != outToken: "Cannot swap token to itself"
            }
            self.inToken = inToken
            self.outToken = outToken
            self.tokenPath = tokenPath
            self.feePath = feePath
        }
    }

    /// UniswapV3SwapperProvider
    ///
    /// A SwapperProvider that pre-computes all swappers at initialization for predictable performance.
    /// When an intermediary token is configured, auto-generates multi-hop routes for any pair
    /// that doesn't have an explicit route, routing through the intermediary.
    /// Returns nil for unconfigured trading pairs that cannot be auto-generated.
    ///
    access(all) struct SwapperProvider : DeFiActions.SwapperProvider, DeFiActions.IdentifiableStruct {
        // Uniswap V3 contract addresses
        access(all) let factoryAddress: EVM.EVMAddress
        access(all) let routerAddress: EVM.EVMAddress
        access(all) let quoterAddress: EVM.EVMAddress

        // Token configuration
        access(all) let tokens: [TokenConfig]

        // Pre-computed swappers
        access(self) let swappers: {String: {DeFiActions.Swapper}}

        // Shared COA capability for all swappers
        access(self) let coaCapability: Capability<auth(EVM.Owner) &EVM.CadenceOwnedAccount>

        // IdentifiableStruct conformance
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?

        init(
            factoryAddress: EVM.EVMAddress,
            routerAddress: EVM.EVMAddress,
            quoterAddress: EVM.EVMAddress,
            tokens: [TokenConfig],
            routes: [RouteConfig],
            coaCapability: Capability<auth(EVM.Owner) &EVM.CadenceOwnedAccount>,
            uniqueID: DeFiActions.UniqueIdentifier?,
            intermediaryToken: TokenConfig?
        ) {
            pre {
                tokens.length >= 2: "Must provide at least 2 tokens"
                routes.length > 0: "Must provide at least one route"
                coaCapability.check(): "Invalid COA capability"
            }

            // Initialize fields
            self.factoryAddress = factoryAddress
            self.routerAddress = routerAddress
            self.quoterAddress = quoterAddress
            self.tokens = tokens
            self.coaCapability = coaCapability
            self.uniqueID = uniqueID
            self.swappers = {}

            // Validate routes reference configured tokens
            let tokenTypes: {Type: Bool} = {}
            for token in tokens {
                tokenTypes[token.flowType] = true
            }

            for route in routes {
                assert(tokenTypes.containsKey(route.inToken),
                    message: "Route inToken not in configured tokens")
                assert(tokenTypes.containsKey(route.outToken),
                    message: "Route outToken not in configured tokens")
            }

            // Validate intermediary token is one of the configured tokens
            if let intermediary = intermediaryToken {
                assert(tokenTypes.containsKey(intermediary.flowType),
                    message: "Intermediary token must be one of the configured tokens")
            }

            // Pre-compute all swappers from explicit routes
            for route in routes {
                let key = self._makeKey(route.inToken, route.outToken)

                let swapper = UniswapV3SwapConnectors.Swapper(
                    factoryAddress: factoryAddress,
                    routerAddress: routerAddress,
                    quoterAddress: quoterAddress,
                    tokenPath: route.tokenPath,
                    feePath: route.feePath,
                    inVault: route.inToken,
                    outVault: route.outToken,
                    coaCapability: coaCapability,
                    uniqueID: uniqueID
                )

                self.swappers[key] = swapper
            }

            // Auto-generate multi-hop routes through intermediary for unconfigured pairs
            if let intermediary = intermediaryToken {
                // Build fee lookup from single-hop explicit routes: "addr1_addr2" -> fee
                let feeLookup: {String: UInt32} = {}
                for route in routes {
                    if route.tokenPath.length == 2 {
                        let addr0 = route.tokenPath[0].toString()
                        let addr1 = route.tokenPath[1].toString()
                        let fee = route.feePath[0]
                        // Store both directions (Uniswap pools are bidirectional)
                        feeLookup[addr0.concat("_").concat(addr1)] = fee
                        feeLookup[addr1.concat("_").concat(addr0)] = fee
                    }
                }

                let intermediaryHex = intermediary.evmAddress.toString()

                // Validate every non-intermediary token has a fee defined with the intermediary
                for token in tokens {
                    if token.flowType == intermediary.flowType {
                        continue
                    }
                    let tokenHex = token.evmAddress.toString()
                    let feeKey = tokenHex.concat("_").concat(intermediaryHex)
                    assert(feeLookup.containsKey(feeKey),
                        message: "Missing fee tier between token ".concat(tokenHex)
                            .concat(" and intermediary ").concat(intermediaryHex)
                            .concat(". An explicit single-hop route must exist for each token paired with the intermediary."))
                }

                // Generate routes for all missing pairs
                var i = 0
                while i < tokens.length {
                    var j = 0
                    while j < tokens.length {
                        if i != j {
                            let ti = tokens[i]
                            let tj = tokens[j]

                            // Skip if either token IS the intermediary
                            if ti.flowType != intermediary.flowType && tj.flowType != intermediary.flowType {
                                let key = self._makeKey(ti.flowType, tj.flowType)

                                // Only generate if no explicit route exists
                                if !self.swappers.containsKey(key) {
                                    let tiHex = ti.evmAddress.toString()
                                    let tjHex = tj.evmAddress.toString()

                                    let fee1 = feeLookup[tiHex.concat("_").concat(intermediaryHex)]!
                                    let fee2 = feeLookup[intermediaryHex.concat("_").concat(tjHex)]!

                                    let swapper = UniswapV3SwapConnectors.Swapper(
                                        factoryAddress: factoryAddress,
                                        routerAddress: routerAddress,
                                        quoterAddress: quoterAddress,
                                        tokenPath: [ti.evmAddress, intermediary.evmAddress, tj.evmAddress],
                                        feePath: [fee1, fee2],
                                        inVault: ti.flowType,
                                        outVault: tj.flowType,
                                        coaCapability: coaCapability,
                                        uniqueID: uniqueID
                                    )

                                    self.swappers[key] = swapper
                                }
                            }

                            // Also generate reverse of explicit routes involving the intermediary
                            // (e.g., if WFLOW->TokenA exists, ensure TokenA->WFLOW also exists)
                            let reverseKey = self._makeKey(tj.flowType, ti.flowType)
                            if self.swappers.containsKey(self._makeKey(ti.flowType, tj.flowType))
                                && !self.swappers.containsKey(reverseKey) {
                                // Look up the route info from explicit routes and create a reversed Swapper
                                for route in routes {
                                    if route.inToken == ti.flowType && route.outToken == tj.flowType {
                                        let reverseSwapper = UniswapV3SwapConnectors.Swapper(
                                            factoryAddress: factoryAddress,
                                            routerAddress: routerAddress,
                                            quoterAddress: quoterAddress,
                                            tokenPath: route.tokenPath.reverse(),
                                            feePath: route.feePath.reverse(),
                                            inVault: tj.flowType,
                                            outVault: ti.flowType,
                                            coaCapability: coaCapability,
                                            uniqueID: uniqueID
                                        )
                                        self.swappers[reverseKey] = reverseSwapper
                                        break
                                    }
                                }
                            }
                        }
                        j = j + 1
                    }
                    i = i + 1
                }
            }
        }

        /// SwapperProvider interface implementation
        ///
        /// Returns a pre-computed swapper for the given trade pair, or nil if not supported.
        ///
        access(all) fun getSwapper(inType: Type, outType: Type): {DeFiActions.Swapper}? {
            return self.swappers[self._makeKey(inType, outType)]
        }

        /// IdentifiableStruct conformance
        ///
        /// Returns information about this provider and all its inner swappers.
        ///
        access(all) fun getComponentInfo(): DeFiActions.ComponentInfo {
            let inner: [DeFiActions.ComponentInfo] = []
            for swapper in self.swappers.values {
                inner.append(swapper.getComponentInfo())
            }
            return DeFiActions.ComponentInfo(
                type: self.getType(),
                id: self.uniqueID?.id,
                innerComponents: inner
            )
        }

        access(contract) view fun copyID(): DeFiActions.UniqueIdentifier? {
            return self.uniqueID
        }

        access(contract) fun setID(_ id: DeFiActions.UniqueIdentifier?) {
            self.uniqueID = id
        }

        /// Helper method to generate consistent dictionary keys
        ///
        access(self) view fun _makeKey(_ inType: Type, _ outType: Type): String {
            return "\(inType.identifier)_TO_\(outType.identifier)"
        }
    }
}
