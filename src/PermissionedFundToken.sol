// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "./WhitelistManager.sol";

/// @title PermissionedFundToken
/// @notice ERC20 representing shares of a tokenized money market fund.
///         Transfers are restricted to whitelisted investors (KYC/AML).
///         NAV is read from an on-chain Chainlink-compatible oracle.
/// @dev    shareValueInCurrency returns the portfolio value scaled by the
///         oracle decimals (8 by convention, i.e. value_EUR * 10^8).
contract PermissionedFundToken is ERC20, AccessControl, Pausable {
    bytes32 public constant FUND_MANAGER_ROLE = keccak256("FUND_MANAGER_ROLE");

    WhitelistManager public immutable whitelist;
    AggregatorV3Interface public immutable navOracle;

    /// @notice Maximum age (in seconds) of the oracle NAV for it to be considered fresh.
    uint256 public immutable maxNavAge;

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
        uint256 _maxNavAge,
        FundMetadata memory metadata
    ) ERC20(name, symbol) {
        require(admin != address(0), "Zero admin");
        require(whitelistManager != address(0), "Zero whitelist");
        require(_navOracle != address(0), "Zero oracle");
        require(_maxNavAge > 0, "Zero maxNavAge");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(FUND_MANAGER_ROLE, admin);
        whitelist = WhitelistManager(whitelistManager);
        navOracle = AggregatorV3Interface(_navOracle);
        maxNavAge = _maxNavAge;

        isin = metadata.isin;
        fundCurrency = metadata.currency;
        fundDomicile = metadata.domicile;
        fundManager = metadata.manager;
    }

    function subscribe(address investor, uint256 shares)
        external
        onlyRole(FUND_MANAGER_ROLE)
        whenNotPaused
    {
        require(whitelist.isWhitelisted(investor), "Investor not whitelisted");
        require(shares > 0, "Zero shares");
        int256 nav = _freshNAV();
        _mint(investor, shares);
        totalSubscriptions += shares;
        emit Subscription(investor, shares, nav);
    }

    function redeem(address investor, uint256 shares)
        external
        onlyRole(FUND_MANAGER_ROLE)
        whenNotPaused
    {
        require(balanceOf(investor) >= shares, "Insufficient shares");
        require(shares > 0, "Zero shares");
        int256 nav = _freshNAV();
        _burn(investor, shares);
        totalRedemptions += shares;
        emit Redemption(investor, shares, nav);
    }

    function latestNAV() external view returns (int256 nav, uint256 updatedAt) {
        (, nav,,updatedAt,) = navOracle.latestRoundData();
    }

    /// @notice Returns the portfolio value of an investor expressed in the fund currency,
    ///         scaled by the oracle decimals (value = EUR × 10^oracleDecimals).
    function shareValueInCurrency(address investor) external view returns (uint256) {
        int256 nav = _freshNAV();
        return (balanceOf(investor) * uint256(nav)) / 1e18;
    }

    function pause() external onlyRole(FUND_MANAGER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(FUND_MANAGER_ROLE) {
        _unpause();
    }

    /// @dev Forced redemption for regulatory or KYC revocation events.
    ///      Bypasses pause and oracle staleness to guarantee funds can always
    ///      be returned to investors. Whitelist is also bypassed on the burn
    ///      path (native to _update). Restricted to DEFAULT_ADMIN_ROLE.
    function forceRedeem(address investor, uint256 shares) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(balanceOf(investor) >= shares, "Insufficient shares");
        require(shares > 0, "Zero shares");
        _burn(investor, shares);
        totalRedemptions += shares;
        (, int256 nav,,,) = navOracle.latestRoundData();
        emit Redemption(investor, shares, nav);
    }

    /// @dev Reads latest oracle round and reverts if NAV is invalid or stale.
    function _freshNAV() internal view returns (int256 nav) {
        uint256 updatedAt;
        (, nav,, updatedAt,) = navOracle.latestRoundData();
        require(nav > 0, "Invalid NAV from oracle");
        require(block.timestamp - updatedAt <= maxNavAge, "Stale NAV");
    }

    /// @dev Enforces whitelist on peer-to-peer transfers AND pauses all
    ///      transfers (including secondary market) during a regulatory freeze.
    ///      Mint/burn (from/to zero) skip the whitelist check and are gated
    ///      by the caller (subscribe/redeem require whenNotPaused; forceRedeem
    ///      intentionally bypasses pause).
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            require(!paused(), "Transfers paused");
            require(whitelist.isWhitelisted(from), "Sender not whitelisted");
            require(whitelist.isWhitelisted(to), "Receiver not whitelisted");
        }
        super._update(from, to, value);
    }
}
