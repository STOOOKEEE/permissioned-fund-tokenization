// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract NAVOracle is AggregatorV3Interface, AccessControl {
    bytes32 public constant PUBLISHER_ROLE = keccak256("PUBLISHER_ROLE");

    struct Round {
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
    }

    string private _isin;
    uint8 private constant DECIMALS = 4; // 16734 = 167.34 EUR
    uint80 private _latestRoundId;
    mapping(uint80 => Round) private _rounds;

    uint256 public minUpdateInterval;
    uint256 public maxNavDeviation; // max % change per update (basis points, 100 = 1%)

    event NAVPublished(uint80 indexed roundId, int256 nav, uint256 timestamp);
    event StaleNAVAlert(uint80 roundId, uint256 secondsSinceUpdate);

    constructor(
        address admin,
        string memory fundIsin,
        int256 initialNav,
        uint256 _minUpdateInterval,
        uint256 _maxNavDeviation
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PUBLISHER_ROLE, admin);
        _isin = fundIsin;
        minUpdateInterval = _minUpdateInterval;
        maxNavDeviation = _maxNavDeviation;

        _latestRoundId = 1;
        _rounds[1] = Round({
            answer: initialNav,
            startedAt: block.timestamp,
            updatedAt: block.timestamp
        });
        emit NAVPublished(1, initialNav, block.timestamp);
    }

    function publishNAV(int256 nav) external onlyRole(PUBLISHER_ROLE) {
        require(nav > 0, "NAV must be positive");

        Round storage prev = _rounds[_latestRoundId];
        require(
            block.timestamp >= prev.updatedAt + minUpdateInterval,
            "Too soon since last update"
        );

        if (maxNavDeviation > 0) {
            int256 deviation = ((nav - prev.answer) * 10000) / prev.answer;
            if (deviation < 0) deviation = -deviation;
            require(
                uint256(deviation) <= maxNavDeviation,
                "NAV deviation exceeds threshold"
            );
        }

        _latestRoundId++;
        _rounds[_latestRoundId] = Round({
            answer: nav,
            startedAt: block.timestamp,
            updatedAt: block.timestamp
        });
        emit NAVPublished(_latestRoundId, nav, block.timestamp);
    }

    function isStale(uint256 maxAge) external view returns (bool) {
        return block.timestamp > _rounds[_latestRoundId].updatedAt + maxAge;
    }

    function navHistory(uint80 fromRound, uint80 toRound)
        external
        view
        returns (int256[] memory navs, uint256[] memory timestamps)
    {
        require(fromRound >= 1 && toRound <= _latestRoundId && fromRound <= toRound, "Invalid range");
        uint256 length = toRound - fromRound + 1;
        navs = new int256[](length);
        timestamps = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            Round storage r = _rounds[fromRound + uint80(i)];
            navs[i] = r.answer;
            timestamps[i] = r.updatedAt;
        }
    }

    // --- AggregatorV3Interface ---

    function decimals() external pure override returns (uint8) {
        return DECIMALS;
    }

    function description() external view override returns (string memory) {
        return string.concat("NAV Oracle / ", _isin);
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(uint80 _roundId)
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        require(_roundId > 0 && _roundId <= _latestRoundId, "Round not found");
        Round storage r = _rounds[_roundId];
        return (_roundId, r.answer, r.startedAt, r.updatedAt, _roundId);
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        Round storage r = _rounds[_latestRoundId];
        return (_latestRoundId, r.answer, r.startedAt, r.updatedAt, _latestRoundId);
    }
}
