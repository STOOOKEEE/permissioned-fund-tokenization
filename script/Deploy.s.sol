// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/WhitelistManager.sol";
import "../src/NAVOracle.sol";
import "../src/PermissionedFundToken.sol";

/// @notice Deployment script with opt-in role separation and admin handoff.
///         Strategy:
///           1. Deploy all contracts with the deployer as initial admin
///              (so the deployer can bootstrap roles and the initial investor).
///           2. Grant operational roles (COMPLIANCE, PUBLISHER, FUND_MANAGER)
///              to the addresses provided via env vars (or keep them on the deployer).
///           3. Whitelist the deployer so demo subscriptions/redemptions can run.
///           4. If ADMIN_ADDRESS is set and different from the deployer
///              (typical for a Gnosis Safe), promote it to DEFAULT_ADMIN_ROLE
///              on all contracts and renounce every role on the deployer.
///         After step 4 the deployer holds no privilege — the Safe has full
///         control and can rotate/revoke any operational role.
contract DeployScript is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        address finalAdmin = vm.envOr("ADMIN_ADDRESS", deployer);
        address compliance = vm.envOr("COMPLIANCE_OFFICER", deployer);
        address publisher = vm.envOr("NAV_PUBLISHER", deployer);
        address fundMgr = vm.envOr("FUND_MANAGER", deployer);

        vm.startBroadcast(deployerKey);

        // 1. Deploy with deployer as initial admin.
        WhitelistManager wl = new WhitelistManager(deployer);

        NAVOracle oracle = new NAVOracle(
            deployer,
            "LU0083138064",
            16_734_00000000, // 167.34 EUR scaled by 10^8 (Chainlink fiat convention)
            12 hours,
            100 // max 1% deviation per update
        );

        PermissionedFundToken token = new PermissionedFundToken(
            "BNP Paribas Euro Money Market - Tokenized",
            "tMMF-EUR",
            deployer,
            address(wl),
            address(oracle),
            48 hours, // maxNavAge: weekend-safe for a daily-publishing MMF
            PermissionedFundToken.FundMetadata({
                isin: "LU0083138064",
                currency: "EUR",
                domicile: "Luxembourg",
                manager: "BNP Paribas Asset Management"
            })
        );

        // 2. Grant operational roles to dedicated addresses if provided.
        if (compliance != deployer) {
            wl.grantRole(wl.COMPLIANCE_ROLE(), compliance);
        }
        if (publisher != deployer) {
            oracle.grantRole(oracle.PUBLISHER_ROLE(), publisher);
        }
        if (fundMgr != deployer) {
            token.grantRole(token.FUND_MANAGER_ROLE(), fundMgr);
        }

        // 3. Bootstrap: whitelist the deployer so demo subscriptions can run.
        wl.addInvestor(deployer);

        // 4. Hand over DEFAULT_ADMIN_ROLE to the Safe and renounce on deployer.
        if (finalAdmin != deployer) {
            // Grant the Safe full super-admin rights.
            wl.grantRole(wl.DEFAULT_ADMIN_ROLE(), finalAdmin);
            oracle.grantRole(oracle.DEFAULT_ADMIN_ROLE(), finalAdmin);
            token.grantRole(token.DEFAULT_ADMIN_ROLE(), finalAdmin);

            // Also grant the Safe every operational role so it can act
            // directly. The Safe can later revoke these for strict separation.
            wl.grantRole(wl.COMPLIANCE_ROLE(), finalAdmin);
            oracle.grantRole(oracle.PUBLISHER_ROLE(), finalAdmin);
            token.grantRole(token.FUND_MANAGER_ROLE(), finalAdmin);

            // Deployer renounces all operational roles it received at construction.
            wl.renounceRole(wl.COMPLIANCE_ROLE(), deployer);
            oracle.renounceRole(oracle.PUBLISHER_ROLE(), deployer);
            token.renounceRole(token.FUND_MANAGER_ROLE(), deployer);

            // Finally, deployer renounces DEFAULT_ADMIN_ROLE on every contract.
            wl.renounceRole(wl.DEFAULT_ADMIN_ROLE(), deployer);
            oracle.renounceRole(oracle.DEFAULT_ADMIN_ROLE(), deployer);
            token.renounceRole(token.DEFAULT_ADMIN_ROLE(), deployer);
        }

        vm.stopBroadcast();

        console.log("--- Deployed contracts ---");
        console.log("Whitelist:   ", address(wl));
        console.log("NAV Oracle:  ", address(oracle));
        console.log("Fund Token:  ", address(token));
        console.log("--- Role holders ---");
        console.log("Admin:       ", finalAdmin);
        console.log("Compliance:  ", compliance);
        console.log("Publisher:   ", publisher);
        console.log("Fund Manager:", fundMgr);
    }
}
