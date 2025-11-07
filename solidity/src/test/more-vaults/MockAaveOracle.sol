// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IAaveOracle} from "@aave-v3-core/contracts/interfaces/IAaveOracle.sol";
import {IPoolAddressesProvider} from "@aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";
/**
 * @title MockAaveOracle
 * @dev Simple in-memory implementation of the Aave oracle used for testing the More Vaults integration.
 *      Allows assigning explicit prices per asset and configuring base currency metadata without extra dependencies.
 *
 * Usage in tests:
 *  - Deploy the mock and optionally adjust the base denomination via {setBaseCurrency}.
 *  - Call {setAssetSource} for each asset you plan to interact with (registry validation relies on it).
 *  - Set the desired price with {setAssetPrice} before invoking vault flows that query NAV or conversions.
 */

contract MockAaveOracle is IAaveOracle {
    error InvalidInput();
    error InvalidPrice();
    error PriceNotSet();

    address private _baseCurrency;
    uint256 private _baseCurrencyUnit;

    mapping(address => address) private _assetSources;
    mapping(address => uint256) private _assetPrices;

    /// @notice Call {setAssetSource} and {setAssetPrice} for every token the vault should understand before running tests.
    ///         Optionally adjust the denomination via {setBaseCurrency} if USD (0x0, 1e8) is not desired.
    constructor() {
        _baseCurrency = address(0);
        _baseCurrencyUnit = 1e8; // mimic USD quotes by default
    }

    /// @notice Configure base currency metadata surfaced through IPriceOracleGetter.
    /// @param baseCurrency Address used as the denomination asset (0x0 interpreted as USD in Aave conventions).
    /// @param baseCurrencyUnit Unit representing one whole baseCurrency (1 ether for native, 1e8 for USD feeds, etc.).
    function setBaseCurrency(address baseCurrency, uint256 baseCurrencyUnit) external {
        _baseCurrency = baseCurrency;
        _baseCurrencyUnit = baseCurrencyUnit;
        emit BaseCurrencySet(baseCurrency, baseCurrencyUnit);
    }

    /// @notice Convenience helper mirroring setAssetSources for a single asset.
    /// @param asset Token whose price source flag is being registered.
    /// @param source Address recorded for compatibility with production flows (value is not consulted for price data).
    function setAssetSource(address asset, address source) external {
        address[] memory assets = new address[](1);
        address[] memory sources = new address[](1);
        assets[0] = asset;
        sources[0] = source;
        _setAssetSources(assets, sources);
    }

    /// @notice Sets the price for a single asset, denominated in the configured base currency unit.
    /// @param asset Token whose price is being set.
    /// @param price Latest price value; must be non-zero.
    function setAssetPrice(address asset, uint256 price) external {
        if (price == 0) revert InvalidPrice();
        _assetPrices[asset] = price;
    }

    // --- IAaveOracle -----------------------------------------------------

    function ADDRESSES_PROVIDER() external pure override returns (IPoolAddressesProvider) {
        return IPoolAddressesProvider(address(0));
    }

    function BASE_CURRENCY() external view override returns (address) {
        return _baseCurrency;
    }

    function BASE_CURRENCY_UNIT() external view override returns (uint256) {
        return _baseCurrencyUnit;
    }

    /// @notice Registers price sources for a group of assets in one call.
    /// @param assets Token addresses being configured.
    /// @param sources Aggregator addresses providing prices for the matching asset index.
    function setAssetSources(address[] calldata assets, address[] calldata sources) external override {
        _setAssetSources(assets, sources);
    }

    /// @notice Unused in this mock; function kept for interface compatibility.
    /// @param fallbackOracle Ignored.
    function setFallbackOracle(address fallbackOracle) external override {
        emit FallbackOracleUpdated(fallbackOracle);
    }

    /// @notice Retrieves prices for the requested assets using the locally stored values.
    /// @param assets Token addresses to fetch prices for.
    /// @return prices Array of prices denominated in the configured base currency unit.
    function getAssetsPrices(address[] calldata assets) external view override returns (uint256[] memory prices) {
        prices = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length;) {
            prices[i] = getAssetPrice(assets[i]);
            unchecked {
                ++i;
            }
        }
    }

    function getSourceOfAsset(address asset) external view override returns (address) {
        return _assetSources[asset];
    }

    /// @notice Always returns address(0) since the fallback oracle concept is not modeled in this mock.
    function getFallbackOracle() external pure override returns (address) {
        return address(0);
    }

    /// @notice Returns the configured price for a single asset.
    /// @param asset Token address to look up.
    /// @return The latest price scaled according to {BASE_CURRENCY_UNIT}. Reverts if the price was not set.
    function getAssetPrice(address asset) public view override returns (uint256) {
        if (_assetSources[asset] == address(0)) {
            return 0;
        }

        uint256 price = _assetPrices[asset];
        if (price == 0) revert PriceNotSet();
        return price;
    }

    // --- Internals -------------------------------------------------------

    /// @dev Internal utility shared between single and batched setters. Stores the mapping and emits updates.
    function _setAssetSources(address[] memory assets, address[] memory sources) internal {
        if (assets.length != sources.length) revert InvalidInput();
        for (uint256 i = 0; i < assets.length;) {
            _assetSources[assets[i]] = sources[i];
            emit AssetSourceUpdated(assets[i], sources[i]);
            unchecked {
                ++i;
            }
        }
    }
}
