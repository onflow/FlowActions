// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {BasicERC20} from "../../src/test/BasicERC20.sol";
import {MockAaveOracle} from "../../src/test/more-vaults/MockAaveOracle.sol";
import {MockAggregatorV2V3} from "../../src/test/more-vaults/MockAggregatorV2V3.sol";

import {VaultsRegistry} from "../../lib/More-Vaults/src/registry/VaultsRegistry.sol";
import {DiamondCutFacet} from "../../lib/More-Vaults/src/facets/DiamondCutFacet.sol";
import {VaultFacet} from "../../lib/More-Vaults/src/facets/VaultFacet.sol";
import {IVaultFacet} from "../../lib/More-Vaults/src/interfaces/facets/IVaultFacet.sol";
import {IDiamondCut} from "../../lib/More-Vaults/src/interfaces/facets/IDiamondCut.sol";
import {MoreVaultsDiamond} from "../../lib/More-Vaults/src/MoreVaultsDiamond.sol";

// NEW: these are commonly required by the 8-arg diamond constructor in newer versions
import {DiamondLoupeFacet} from "../../lib/More-Vaults/src/facets/DiamondLoupeFacet.sol";
import {AccessControlFacet} from "../../lib/More-Vaults/src/facets/AccessControlFacet.sol";
import {ConfigurationFacet} from "../../lib/More-Vaults/src/facets/ConfigurationFacet.sol";

contract VaultFacetMinimalTest is Test {
    MockAaveOracle internal oracle;
    MockAggregatorV2V3 internal underlyingFeed;
    VaultsRegistry internal registry;

    DiamondCutFacet internal diamondCutFacet;
    DiamondLoupeFacet internal diamondLoupeFacet;
    AccessControlFacet internal accessControlFacet;
    ConfigurationFacet internal configurationFacet;

    VaultFacet internal vaultFacetImpl;

    MoreVaultsDiamond internal diamond;
    IVaultFacet internal vault;

    BasicERC20 internal underlying;
    BasicERC20 internal wrappedNative;
    BasicERC20 internal usdStable;

    address internal feeRecipient = address(0xFEE);
    address internal user = address(0xA11CE);

    // roles (many versions require these)
    address internal owner = address(this);
    address internal factory = address(0xFAc7);
    bool internal isHub = false;

    uint256 internal constant INITIAL_ASSETS = 1_000 ether;
    uint256 internal constant DEPOSIT_CAPACITY = 1_000_000 ether;

    function setUp() public {
        underlying = new BasicERC20("Mock USD", "mUSD");
        wrappedNative = new BasicERC20("Mock WFLOW", "mWFLOW");
        usdStable = new BasicERC20("USD Stable", "USDS");

        oracle = new MockAaveOracle();
        underlyingFeed = new MockAggregatorV2V3(18, "Underlying");
        underlyingFeed.updateAnswer(int256(1e8), 0);

        oracle.setAssetSource(address(underlying), address(underlyingFeed));
        oracle.setAssetPrice(address(underlying), 1e8);

        registry = new VaultsRegistry();

        // FIX #1: correct arg order + 3 args
        registry.initialize(owner, address(oracle), address(usdStable));

        diamondCutFacet = new DiamondCutFacet();
        accessControlFacet = new AccessControlFacet(); // FIX #2: required by diamond ctor
        vaultFacetImpl = new VaultFacet();

        registry.addFacet(address(diamondCutFacet), _diamondCutSelectors());
        registry.addFacet(address(vaultFacetImpl), _vaultFacetSelectors());

        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        cuts[0] = IDiamondCut.FacetCut({
            facetAddress: address(vaultFacetImpl),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _vaultFacetSelectors(),
            initData: abi.encode(
                "Test More Vault", "tmMORE", address(underlying), feeRecipient, uint96(0), DEPOSIT_CAPACITY
            )
        });

        // FIX #3: pass all 8 args, including accessControlFacetInitData
        //
        // NOTE: You MUST encode whatever your AccessControlFacet expects.
        // If your AccessControlFacet has an initializer like `init(address owner)` then use abi.encode(owner).
        // If it uses something else, adjust accordingly.
        bytes memory accessControlFacetInitData = abi.encode(owner);

        diamond = new MoreVaultsDiamond(
            address(diamondCutFacet),
            address(accessControlFacet),
            address(registry),
            address(wrappedNative),
            factory,
            isHub,
            cuts,
            accessControlFacetInitData
        );

        vault = IVaultFacet(address(diamond));

        underlying.mint(user, INITIAL_ASSETS);
    }

    function testVaultMetadata() public view {
        assertEq(vault.asset(), address(underlying), "asset mismatch");
        assertEq(vault.name(), "Test More Vault");
        assertEq(vault.symbol(), "tmMORE");
        assertEq(vault.decimals(), underlying.decimals() + 2); // decimals offset of 2
    }

    function testDepositAndTotalAssets() public {
        assertEq(vault.totalAssets(), 0, "pre-deposit total assets");

        vm.startPrank(user);
        underlying.approve(address(vault), INITIAL_ASSETS);
        uint256 sharesMinted = vault.deposit(INITIAL_ASSETS, user);
        vm.stopPrank();

        assertEq(vault.totalAssets(), INITIAL_ASSETS, "total assets after deposit");
        // With decimals offset (2) the initial share issue is scaled by 100.
        assertEq(sharesMinted, INITIAL_ASSETS * 100, "unexpected share mint amount");
        assertEq(vault.balanceOf(user), sharesMinted, "share balance mismatch");
    }

    function testConvertAndRedeemFlow() public {
        vm.startPrank(user);
        underlying.approve(address(vault), INITIAL_ASSETS);
        uint256 shares = vault.deposit(INITIAL_ASSETS, user);
        vm.stopPrank();

        uint256 quoteShares = vault.convertToShares(100 ether);
        assertEq(quoteShares, 100 ether * 100, "convertToShares scaling");

        uint256 previewAssets = vault.previewRedeem(shares);
        assertEq(previewAssets, INITIAL_ASSETS, "previewRedeem should mirror deposit");

        vm.startPrank(user);
        uint256 assetsOut = vault.redeem(shares, user, user);
        vm.stopPrank();

        assertEq(assetsOut, INITIAL_ASSETS, "redeem output mismatch");
        assertEq(vault.totalAssets(), 0, "total assets after redeem");
        assertEq(vault.balanceOf(user), 0, "user share balance after redeem");
    }

    // ---------------------------------------------------------------------
    // Helper utilities
    // ---------------------------------------------------------------------

    function _diamondCutSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IDiamondCut.diamondCut.selector;
    }

    function _vaultFacetSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](29);
        selectors[0] = IERC20Metadata.name.selector;
        selectors[1] = IERC20Metadata.symbol.selector;
        selectors[2] = IERC20Metadata.decimals.selector;
        selectors[3] = IERC20.balanceOf.selector;
        selectors[4] = IERC20.approve.selector;
        selectors[5] = IERC20.transfer.selector;
        selectors[6] = IERC20.transferFrom.selector;
        selectors[7] = IERC20.allowance.selector;
        selectors[8] = IERC20.totalSupply.selector;
        selectors[9] = IERC4626.asset.selector;
        selectors[10] = IERC4626.totalAssets.selector;
        selectors[11] = IERC4626.convertToAssets.selector;
        selectors[12] = IERC4626.convertToShares.selector;
        selectors[13] = IERC4626.maxDeposit.selector;
        selectors[14] = IERC4626.previewDeposit.selector;
        selectors[15] = IERC4626.deposit.selector;
        selectors[16] = IERC4626.maxMint.selector;
        selectors[17] = IERC4626.previewMint.selector;
        selectors[18] = IERC4626.mint.selector;
        selectors[19] = IERC4626.maxWithdraw.selector;
        selectors[20] = IERC4626.previewWithdraw.selector;
        selectors[21] = IERC4626.withdraw.selector;
        selectors[22] = IERC4626.maxRedeem.selector;
        selectors[23] = IERC4626.previewRedeem.selector;
        selectors[24] = IERC4626.redeem.selector;
        selectors[25] = bytes4(keccak256("deposit(address[],uint256[],address)"));
        selectors[26] = IVaultFacet.paused.selector;
        selectors[27] = IVaultFacet.pause.selector;
        selectors[28] = IVaultFacet.unpause.selector;
    }
}
