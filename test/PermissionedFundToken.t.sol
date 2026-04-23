// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/WhitelistManager.sol";
import "../src/NAVOracle.sol";
import "../src/PermissionedFundToken.sol";

contract PermissionedFundTokenTest is Test {
    WhitelistManager whitelist;
    NAVOracle oracle;
    PermissionedFundToken token;

    address admin = makeAddr("admin");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");

    int256 constant NAV_167_34 = 16_734_00000000;
    int256 constant NAV_167_50 = 16_750_00000000;

    uint256 constant MAX_NAV_AGE = 48 hours;

    function setUp() public {
        vm.startPrank(admin);
        whitelist = new WhitelistManager(admin);
        oracle = new NAVOracle(admin, "LU0083138064", NAV_167_34, 12 hours, 100);
        token = new PermissionedFundToken(
            "BNP Paribas Euro Money Market - Tokenized",
            "tMMF-EUR",
            admin,
            address(whitelist),
            address(oracle),
            MAX_NAV_AGE,
            PermissionedFundToken.FundMetadata({
                isin: "LU0083138064",
                currency: "EUR",
                domicile: "Luxembourg",
                manager: "BNP Paribas Asset Management"
            })
        );
        whitelist.addInvestor(alice);
        whitelist.addInvestor(bob);
        vm.stopPrank();
    }

    function test_fundMetadata() public view {
        assertEq(token.name(), "BNP Paribas Euro Money Market - Tokenized");
        assertEq(token.symbol(), "tMMF-EUR");
        assertEq(keccak256(bytes(token.isin())), keccak256("LU0083138064"));
        assertEq(keccak256(bytes(token.fundCurrency())), keccak256("EUR"));
        assertEq(token.maxNavAge(), MAX_NAV_AGE);
    }

    function test_latestNAV() public view {
        (int256 nav, uint256 updatedAt) = token.latestNAV();
        assertEq(nav, NAV_167_34);
        assertGt(updatedAt, 0);
    }

    function test_subscribe() public {
        vm.prank(admin);
        token.subscribe(alice, 10e18);
        assertEq(token.balanceOf(alice), 10e18);
        assertEq(token.totalSubscriptions(), 10e18);
    }

    function test_subscribe_revertIfNotWhitelisted() public {
        vm.prank(admin);
        vm.expectRevert("Investor not whitelisted");
        token.subscribe(charlie, 1e18);
    }

    function test_subscribe_revertIfNotManager() public {
        vm.prank(alice);
        vm.expectRevert();
        token.subscribe(alice, 1e18);
    }

    function test_subscribe_revertIfStaleNAV() public {
        vm.warp(block.timestamp + MAX_NAV_AGE + 1);
        vm.prank(admin);
        vm.expectRevert("Stale NAV");
        token.subscribe(alice, 1e18);
    }

    function test_redeem() public {
        vm.startPrank(admin);
        token.subscribe(alice, 10e18);
        token.redeem(alice, 4e18);
        vm.stopPrank();
        assertEq(token.balanceOf(alice), 6e18);
        assertEq(token.totalRedemptions(), 4e18);
    }

    function test_redeem_revertInsufficientShares() public {
        vm.startPrank(admin);
        token.subscribe(alice, 1e18);
        vm.expectRevert("Insufficient shares");
        token.redeem(alice, 2e18);
        vm.stopPrank();
    }

    function test_redeem_revertIfStaleNAV() public {
        vm.prank(admin);
        token.subscribe(alice, 5e18);
        vm.warp(block.timestamp + MAX_NAV_AGE + 1);
        vm.prank(admin);
        vm.expectRevert("Stale NAV");
        token.redeem(alice, 1e18);
    }

    function test_transfer_betweenWhitelisted() public {
        vm.prank(admin);
        token.subscribe(alice, 5e18);

        vm.prank(alice);
        token.transfer(bob, 2e18);

        assertEq(token.balanceOf(alice), 3e18);
        assertEq(token.balanceOf(bob), 2e18);
    }

    function test_transfer_revertToNonWhitelisted() public {
        vm.prank(admin);
        token.subscribe(alice, 5e18);

        vm.prank(alice);
        vm.expectRevert("Receiver not whitelisted");
        token.transfer(charlie, 1e18);
    }

    function test_transfer_revertFromRemovedInvestor() public {
        vm.startPrank(admin);
        token.subscribe(alice, 5e18);
        whitelist.removeInvestor(alice);
        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert("Sender not whitelisted");
        token.transfer(bob, 1e18);
    }

    function test_shareValue() public {
        vm.prank(admin);
        token.subscribe(alice, 10e18);

        // 10 shares × 167.34 EUR = 1673.40 EUR → scaled by 10^8 = 167_340_00000000
        uint256 value = token.shareValueInCurrency(alice);
        assertEq(value, uint256(NAV_167_34) * 10);
    }

    function test_shareValue_revertIfStaleNAV() public {
        vm.prank(admin);
        token.subscribe(alice, 5e18);
        vm.warp(block.timestamp + MAX_NAV_AGE + 1);
        vm.expectRevert("Stale NAV");
        token.shareValueInCurrency(alice);
    }

    function test_subscriptionEmitsOracleNAV() public {
        vm.warp(block.timestamp + 13 hours);
        vm.prank(admin);
        oracle.publishNAV(NAV_167_50);

        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit PermissionedFundToken.Subscription(alice, 10e18, NAV_167_50);
        token.subscribe(alice, 10e18);
    }

    function test_pause_blocksSubscriptions() public {
        vm.startPrank(admin);
        token.pause();
        vm.expectRevert();
        token.subscribe(alice, 1e18);
        vm.stopPrank();
    }

    function test_pause_blocksSecondaryTransfers() public {
        vm.prank(admin);
        token.subscribe(alice, 5e18);

        vm.prank(admin);
        token.pause();

        vm.prank(alice);
        vm.expectRevert("Transfers paused");
        token.transfer(bob, 1e18);
    }

    function test_unpause_resumesOperations() public {
        vm.startPrank(admin);
        token.pause();
        token.unpause();
        token.subscribe(alice, 1e18);
        vm.stopPrank();
        assertEq(token.balanceOf(alice), 1e18);
    }

    function test_forceRedeem_bypassesPauseAndStaleness() public {
        vm.prank(admin);
        token.subscribe(alice, 10e18);

        vm.prank(admin);
        token.pause();
        vm.warp(block.timestamp + MAX_NAV_AGE + 1);

        vm.prank(admin);
        token.forceRedeem(alice, 10e18);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_forceRedeem_revertIfNotAdmin() public {
        vm.prank(admin);
        token.subscribe(alice, 5e18);

        vm.prank(alice);
        vm.expectRevert();
        token.forceRedeem(alice, 1e18);
    }

    function test_constructor_revertZeroMaxNavAge() public {
        vm.expectRevert("Zero maxNavAge");
        new PermissionedFundToken(
            "X", "X", admin, address(whitelist), address(oracle), 0,
            PermissionedFundToken.FundMetadata("", "", "", "")
        );
    }
}
