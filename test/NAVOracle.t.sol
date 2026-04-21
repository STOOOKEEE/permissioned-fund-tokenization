// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/NAVOracle.sol";

contract NAVOracleTest is Test {
    NAVOracle oracle;
    address admin = makeAddr("admin");
    address publisher = makeAddr("publisher");
    address stranger = makeAddr("stranger");

    function setUp() public {
        vm.prank(admin);
        oracle = new NAVOracle(
            admin,
            "LU0083138064",
            16734, // 167.34 EUR
            12 hours,
            100 // max 1% deviation
        );
    }

    function test_initialState() public view {
        assertEq(oracle.decimals(), 4);
        (uint80 roundId, int256 answer,,,) = oracle.latestRoundData();
        assertEq(roundId, 1);
        assertEq(answer, 16734);
    }

    function test_description() public view {
        string memory desc = oracle.description();
        assertEq(desc, "NAV Oracle / LU0083138064");
    }

    function test_publishNAV() public {
        vm.warp(block.timestamp + 13 hours);
        vm.prank(admin);
        oracle.publishNAV(16738); // +0.024%

        (uint80 roundId, int256 answer,,,) = oracle.latestRoundData();
        assertEq(roundId, 2);
        assertEq(answer, 16738);
    }

    function test_publishNAV_revertTooSoon() public {
        vm.warp(block.timestamp + 1 hours);
        vm.prank(admin);
        vm.expectRevert("Too soon since last update");
        oracle.publishNAV(16738);
    }

    function test_publishNAV_revertExcessiveDeviation() public {
        vm.warp(block.timestamp + 13 hours);
        vm.prank(admin);
        vm.expectRevert("NAV deviation exceeds threshold");
        oracle.publishNAV(17000); // +1.6% > 1% threshold
    }

    function test_publishNAV_revertUnauthorized() public {
        vm.warp(block.timestamp + 13 hours);
        vm.prank(stranger);
        vm.expectRevert();
        oracle.publishNAV(16738);
    }

    function test_publishNAV_revertZero() public {
        vm.warp(block.timestamp + 13 hours);
        vm.prank(admin);
        vm.expectRevert("NAV must be positive");
        oracle.publishNAV(0);
    }

    function test_getRoundData() public {
        vm.warp(block.timestamp + 13 hours);
        vm.prank(admin);
        oracle.publishNAV(16738);

        (uint80 roundId, int256 answer,,,) = oracle.getRoundData(1);
        assertEq(roundId, 1);
        assertEq(answer, 16734);

        (roundId, answer,,,) = oracle.getRoundData(2);
        assertEq(roundId, 2);
        assertEq(answer, 16738);
    }

    function test_getRoundData_revertInvalid() public {
        vm.expectRevert("Round not found");
        oracle.getRoundData(0);

        vm.expectRevert("Round not found");
        oracle.getRoundData(99);
    }

    function test_navHistory() public {
        vm.startPrank(admin);
        for (uint256 i = 0; i < 5; i++) {
            vm.warp(block.timestamp + 13 hours);
            oracle.publishNAV(int256(16734 + i + 1));
        }
        vm.stopPrank();

        (int256[] memory navs, uint256[] memory timestamps) = oracle.navHistory(1, 6);
        assertEq(navs.length, 6);
        assertEq(navs[0], 16734);
        assertEq(navs[5], 16739);
        assertGt(timestamps[5], timestamps[0]);
    }

    function test_isStale() public {
        assertFalse(oracle.isStale(24 hours));

        vm.warp(block.timestamp + 25 hours);
        assertTrue(oracle.isStale(24 hours));
    }

    function test_multiplePublishers() public {
        vm.startPrank(admin);
        oracle.grantRole(oracle.PUBLISHER_ROLE(), publisher);
        vm.stopPrank();

        vm.warp(block.timestamp + 13 hours);
        vm.prank(publisher);
        oracle.publishNAV(16738);

        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, 16738);
    }
}
