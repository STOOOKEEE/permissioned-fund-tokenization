// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/WhitelistManager.sol";
import "../src/NAVOracle.sol";
import "../src/PermissionedFundToken.sol";

contract FundLifecycleTest is Test {
    WhitelistManager whitelist;
    NAVOracle oracle;
    PermissionedFundToken token;

    address admin = makeAddr("fundManager");
    address investorA = makeAddr("institutionalA");
    address investorB = makeAddr("institutionalB");
    address unauthorized = makeAddr("unauthorized");

    int256 constant NAV_167_34 = 16_734_00000000;
    int256 constant NAV_167_38 = 16_738_00000000;
    int256 constant NAV_167_42 = 16_742_00000000;
    int256 constant NAV_167_46 = 16_746_00000000;

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
        whitelist.addInvestor(investorA);
        whitelist.addInvestor(investorB);
        vm.stopPrank();
    }

    function test_fullFundLifecycle() public {
        vm.startPrank(admin);

        // Day 1: two institutions subscribe at NAV 167.34
        token.subscribe(investorA, 100e18);
        token.subscribe(investorB, 50e18);
        assertEq(token.totalSupply(), 150e18);

        // Day 2: NAV oracle updates (money market daily yield)
        vm.warp(block.timestamp + 13 hours);
        oracle.publishNAV(NAV_167_38); // +0.024%

        // Day 2: investorA partially redeems at new NAV
        token.redeem(investorA, 30e18);
        assertEq(token.balanceOf(investorA), 70e18);

        vm.stopPrank();

        // investorA transfers shares to investorB (secondary market)
        vm.prank(investorA);
        token.transfer(investorB, 20e18);

        assertEq(token.balanceOf(investorA), 50e18);
        assertEq(token.balanceOf(investorB), 70e18);
        assertEq(token.totalSupply(), 120e18);

        // unauthorized cannot receive
        vm.prank(investorA);
        vm.expectRevert("Receiver not whitelisted");
        token.transfer(unauthorized, 1e18);
    }

    function test_navDrivenValuation() public {
        vm.startPrank(admin);
        token.subscribe(investorA, 100e18);

        // NAV goes up over 3 days
        vm.warp(block.timestamp + 13 hours);
        oracle.publishNAV(NAV_167_38);
        vm.warp(block.timestamp + 13 hours);
        oracle.publishNAV(NAV_167_42);
        vm.warp(block.timestamp + 13 hours);
        oracle.publishNAV(NAV_167_46);
        vm.stopPrank();

        // Portfolio value reflects latest NAV, scaled by 10^8 (oracle decimals).
        uint256 value = token.shareValueInCurrency(investorA);
        assertEq(value, uint256(NAV_167_46) * 100);
    }

    function test_regulatoryFreeze() public {
        vm.startPrank(admin);
        token.subscribe(investorA, 100e18);

        token.pause();

        vm.expectRevert();
        token.subscribe(investorB, 50e18);
        vm.expectRevert();
        token.redeem(investorA, 10e18);
        vm.stopPrank();

        // Secondary transfers also frozen during regulatory pause (HIGH-3 fix).
        vm.prank(investorA);
        vm.expectRevert("Transfers paused");
        token.transfer(investorB, 1e18);

        vm.startPrank(admin);
        token.unpause();
        token.redeem(investorA, 10e18);
        assertEq(token.balanceOf(investorA), 90e18);
        vm.stopPrank();
    }

    function test_kycRevocation() public {
        vm.startPrank(admin);
        token.subscribe(investorA, 100e18);

        whitelist.removeInvestor(investorA);
        vm.stopPrank();

        vm.prank(investorA);
        vm.expectRevert("Sender not whitelisted");
        token.transfer(investorB, 10e18);

        vm.prank(admin);
        token.redeem(investorA, 100e18);
        assertEq(token.balanceOf(investorA), 0);
    }

    function test_emergencyNavAfterMarketShock() public {
        vm.startPrank(admin);
        token.subscribe(investorA, 100e18);

        // Simulate a 2% market shock: normal publish would revert on deviation.
        vm.warp(block.timestamp + 13 hours);
        int256 shockedNav = NAV_167_34 * 102 / 100;
        vm.expectRevert("NAV deviation exceeds threshold");
        oracle.publishNAV(shockedNav);

        // Admin uses emergency publish with reason.
        oracle.emergencyPublishNAV(shockedNav, "ECB rate hike, +2% MMF repricing");

        // Subscriptions continue at the new NAV with an audit trail on-chain.
        token.subscribe(investorB, 10e18);
        vm.stopPrank();

        (, int256 nav,,,) = oracle.latestRoundData();
        assertEq(nav, shockedNav);
    }
}
