// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "./WhitelistManager.sol";

contract PermissionedFundToken is ERC20, AccessControl, Pausable {
    bytes32 public constant FUND_MANAGER_ROLE = keccak256("FUND_MANAGER_ROLE");

    WhitelistManager public immutable whitelist;
    AggregatorV3Interface public immutable navOracle;

    string public isin;
    string public fundCurrency;
    string public fundDomicile;
    string public fundManager;

    uint256 public totalSubscriptions;
    uint256 public totalRedemptions;

    event Subscription(address indexed investor, uint256 shares, int256 navAtTime);
    event Redemption(address indexed investor, uint256 shares, int256 navAtTime);

    struct FundMetadata {
        string isin;
        string currency;
        string domicile;
        string manager;
    }

    constructor(
        string memory name,
        string memory symbol,
        address admin,
        address whitelistManager,
        address _navOracle,
        FundMetadata memory metadata
    ) ERC20(name, symbol) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(FUND_MANAGER_ROLE, admin);
        whitelist = WhitelistManager(whitelistManager);
        navOracle = AggregatorV3Interface(_navOracle);

        isin = metadata.isin;
        fundCurrency = metadata.currency;
        fundDomicile = metadata.domicile;
        fundManager = metadata.manager;
    }

    function subscribe(address investor, uint256 shares) external onlyRole(FUND_MANAGER_ROLE) whenNotPaused {
        require(whitelist.isWhitelisted(investor), "Investor not whitelisted");
        require(shares > 0, "Zero shares");
        (, int256 nav,,,) = navOracle.latestRoundData();
        require(nav > 0, "Invalid NAV from oracle");
        _mint(investor, shares);
        totalSubscriptions += shares;
        emit Subscription(investor, shares, nav);
    }

    function redeem(address investor, uint256 shares) external onlyRole(FUND_MANAGER_ROLE) whenNotPaused {
        require(balanceOf(investor) >= shares, "Insufficient shares");
        require(shares > 0, "Zero shares");
        (, int256 nav,,,) = navOracle.latestRoundData();
        require(nav > 0, "Invalid NAV from oracle");
        _burn(investor, shares);
        totalRedemptions += shares;
        emit Redemption(investor, shares, nav);
    }

    function latestNAV() external view returns (int256 nav, uint256 updatedAt) {
        (, nav,,updatedAt,) = navOracle.latestRoundData();
    }

    function shareValueInCurrency(address investor) external view returns (uint256) {
        (, int256 nav,,,) = navOracle.latestRoundData();
        require(nav > 0, "Invalid NAV");
        return (balanceOf(investor) * uint256(nav)) / 1e18;
    }

    function pause() external onlyRole(FUND_MANAGER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(FUND_MANAGER_ROLE) {
        _unpause();
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            require(whitelist.isWhitelisted(from), "Sender not whitelisted");
            require(whitelist.isWhitelisted(to), "Receiver not whitelisted");
        }
        super._update(from, to, value);
    }
}
