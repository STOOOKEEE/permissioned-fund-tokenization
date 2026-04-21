// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract WhitelistManager is AccessControl {
    bytes32 public constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");

    mapping(address => bool) private _whitelisted;
    uint256 private _whitelistedCount;

    event InvestorAdded(address indexed investor);
    event InvestorRemoved(address indexed investor);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(COMPLIANCE_ROLE, admin);
    }

    function addInvestor(address investor) external onlyRole(COMPLIANCE_ROLE) {
        require(investor != address(0), "Zero address");
        require(!_whitelisted[investor], "Already whitelisted");
        _whitelisted[investor] = true;
        _whitelistedCount++;
        emit InvestorAdded(investor);
    }

    function removeInvestor(address investor) external onlyRole(COMPLIANCE_ROLE) {
        require(_whitelisted[investor], "Not whitelisted");
        _whitelisted[investor] = false;
        _whitelistedCount--;
        emit InvestorRemoved(investor);
    }

    function addInvestorsBatch(address[] calldata investors) external onlyRole(COMPLIANCE_ROLE) {
        for (uint256 i = 0; i < investors.length; i++) {
            if (investors[i] != address(0) && !_whitelisted[investors[i]]) {
                _whitelisted[investors[i]] = true;
                _whitelistedCount++;
                emit InvestorAdded(investors[i]);
            }
        }
    }

    function isWhitelisted(address investor) external view returns (bool) {
        return _whitelisted[investor];
    }

    function whitelistedCount() external view returns (uint256) {
        return _whitelistedCount;
    }
}
