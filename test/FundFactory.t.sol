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

    function setUp() public {
        vm.startPrank(admin);
        whitelist = new WhitelistManager(admin);
        oracle = new NAVOracle(admin, "LU0083138064", 16734, 12 hours, 100);
        token = new PermissionedFundToken(
            "BNP Paribas Euro Money Market - Tokenized",
            "tMMF-EUR",
            admin,
            address(whitelist),
            address(oracle),
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
        oracle.publishNAV(16738); // +0.024%

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
        oracle.publishNAV(16738);
        vm.warp(block.timestamp + 13 hours);
        oracle.publishNAV(16742);
        vm.warp(block.timestamp + 13 hours);
        oracle.publishNAV(16746);
        vm.stopPrank();

        // Portfolio value reflects latest NAV
        uint256 value = token.shareValueInCurrency(investorA);
        assertEq(value, 16746 * 100); // 100 shares * 167.46 EUR
    }

    function test_regulatoryFreeze() public {
        vm.startPrank(admin);
        token.subscribe(investorA, 100e18);

        token.pause();

        vm.expectRevert();
        token.subscribe(investorB, 50e18);
        vm.expectRevert();
        token.redeem(investorA, 10e18);

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
}
