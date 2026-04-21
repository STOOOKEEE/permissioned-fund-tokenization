// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/WhitelistManager.sol";
import "../src/NAVOracle.sol";
import "../src/PermissionedFundToken.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        WhitelistManager wl = new WhitelistManager(deployer);

        NAVOracle oracle = new NAVOracle(
            deployer,
            "LU0083138064",
            16734, // 167.34 EUR initial NAV
            12 hours,
            100 // max 1% deviation per update
        );

        PermissionedFundToken token = new PermissionedFundToken(
            "BNP Paribas Euro Money Market - Tokenized",
            "tMMF-EUR",
            deployer,
            address(wl),
            address(oracle),
            PermissionedFundToken.FundMetadata({
                isin: "LU0083138064",
                currency: "EUR",
                domicile: "Luxembourg",
                manager: "BNP Paribas Asset Management"
            })
        );

        wl.addInvestor(deployer);

        vm.stopBroadcast();

        console.log("Whitelist:", address(wl));
        console.log("NAV Oracle:", address(oracle));
        console.log("Fund Token:", address(token));
    }
}
