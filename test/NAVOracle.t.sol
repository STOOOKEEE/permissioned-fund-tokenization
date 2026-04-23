// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/NAVOracle.sol";

contract NAVOracleTest is Test {
    NAVOracle oracle;
    address admin = makeAddr("admin");
    address publisher = makeAddr("publisher");
    address stranger = makeAddr("stranger");

    // NAV is scaled by 10^8 (Chainlink fiat convention). 167.34 EUR → 16_734_00000000.
    int256 constant NAV_167_34 = 16_734_00000000;
    int256 constant NAV_167_38 = 16_738_00000000;
    int256 constant NAV_170_00 = 17_000_00000000;

    function setUp() public {
        vm.prank(admin);
        oracle = new NAVOracle(
            admin,
            "LU0083138064",
            NAV_167_34,
            12 hours,
            100 // max 1% deviation
        );
    }

    function test_initialState() public view {
        assertEq(oracle.decimals(), 8);
        (uint80 roundId, int256 answer,,,) = oracle.latestRoundData();
        assertEq(roundId, 1);
        assertEq(answer, NAV_167_34);
    }

    function test_constructor_revertZeroInitialNav() public {
        vm.expectRevert("Initial NAV must be positive");
        new NAVOracle(admin, "X", 0, 12 hours, 100);
    }

    function test_constructor_revertNegativeInitialNav() public {
        vm.expectRevert("Initial NAV must be positive");
        new NAVOracle(admin, "X", -1, 12 hours, 100);
    }

    function test_constructor_revertZeroAdmin() public {
        vm.expectRevert("Zero admin");
        new NAVOracle(address(0), "X", NAV_167_34, 12 hours, 100);
    }

    function test_description() public view {
        string memory desc = oracle.description();
        assertEq(desc, "NAV Oracle / LU0083138064");
    }

    function test_publishNAV() public {
        vm.warp(block.timestamp + 13 hours);
        vm.prank(admin);
        oracle.publishNAV(NAV_167_38); // +0.024%

        (uint80 roundId, int256 answer,,,) = oracle.latestRoundData();
        assertEq(roundId, 2);
        assertEq(answer, NAV_167_38);
    }

    function test_publishNAV_revertTooSoon() public {
        vm.warp(block.timestamp + 1 hours);
        vm.prank(admin);
        vm.expectRevert("Too soon since last update");
        oracle.publishNAV(NAV_167_38);
    }

    function test_publishNAV_revertExcessiveDeviation() public {
        vm.warp(block.timestamp + 13 hours);
        vm.prank(admin);
        vm.expectRevert("NAV deviation exceeds threshold");
        oracle.publishNAV(NAV_170_00); // +1.59% > 1% threshold
    }

    function test_publishNAV_revertUnauthorized() public {
        vm.warp(block.timestamp + 13 hours);
        vm.prank(stranger);
        vm.expectRevert();
        oracle.publishNAV(NAV_167_38);
    }

    function test_publishNAV_revertZero() public {
        vm.warp(block.timestamp + 13 hours);
        vm.prank(admin);
        vm.expectRevert("NAV must be positive");
        oracle.publishNAV(0);
    }

    function test_publishNAV_revertNegative() public {
        vm.warp(block.timestamp + 13 hours);
        vm.prank(admin);
        vm.expectRevert("NAV must be positive");
        oracle.publishNAV(-1);
    }

    function test_emergencyPublishNAV_bypassesDeviation() public {
        vm.warp(block.timestamp + 13 hours);
        vm.prank(admin);
        oracle.emergencyPublishNAV(NAV_170_00, "Market event: ECB policy shock");

        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, NAV_170_00);
    }

    function test_emergencyPublishNAV_revertIfNotAdmin() public {
        vm.warp(block.timestamp + 13 hours);
        // Publisher alone cannot emergency-publish (requires DEFAULT_ADMIN_ROLE).
        vm.startPrank(admin);
        oracle.grantRole(oracle.PUBLISHER_ROLE(), publisher);
        vm.stopPrank();
        vm.prank(publisher);
        vm.expectRevert();
        oracle.emergencyPublishNAV(NAV_170_00, "test");
    }

    function test_emergencyPublishNAV_revertEmptyReason() public {
        vm.warp(block.timestamp + 13 hours);
        vm.prank(admin);
        vm.expectRevert("Reason required");
        oracle.emergencyPublishNAV(NAV_170_00, "");
    }

    function test_emergencyPublishNAV_stillRequiresCooldown() public {
        vm.prank(admin);
        vm.expectRevert("Too soon since last update");
        oracle.emergencyPublishNAV(NAV_170_00, "test");
    }

    function test_getRoundData() public {
        vm.warp(block.timestamp + 13 hours);
        vm.prank(admin);
        oracle.publishNAV(NAV_167_38);

        (uint80 roundId, int256 answer,,,) = oracle.getRoundData(1);
        assertEq(roundId, 1);
        assertEq(answer, NAV_167_34);

        (roundId, answer,,,) = oracle.getRoundData(2);
        assertEq(roundId, 2);
        assertEq(answer, NAV_167_38);
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
            oracle.publishNAV(NAV_167_34 + int256((i + 1) * 1e8));
        }
        vm.stopPrank();

        (int256[] memory navs, uint256[] memory timestamps) = oracle.navHistory(1, 6);
        assertEq(navs.length, 6);
        assertEq(navs[0], NAV_167_34);
        assertEq(navs[5], NAV_167_34 + int256(5 * 1e8));
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
        oracle.publishNAV(NAV_167_38);

        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, NAV_167_38);
    }
}
