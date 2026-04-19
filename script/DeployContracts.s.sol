// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Script, console } from "forge-std/Script.sol";
import { LiquiPoolHandler } from "../src/LiquiPool.sol";
import { LiquiPoolVault } from "../src/LiquiPoolVault.sol";

contract DeployContracts is Script {

    // ── Anvil default account #0 ─────────────────
    address constant POOL_MANAGER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    // ── amounts in wei ───────────────────────────
    uint256 constant MONTHLY_CONTRIBUTION    = 10000000000000000;   // 0.01 ether
    uint256 constant SECURITY_DEPOSIT        = 100000000000000000;  // 0.1  ether
    uint256 constant GRACE_PENALTY_FEE       = 1000000000000000;    // 0.001 ether

    // ── timing in seconds ────────────────────────
    uint256 constant PRIMARY_WINDOW_DURATION = 420;   // 7 minutes
    uint256 constant GRACE_PERIOD_DURATION   = 240;   // 4 minutes

    function run() external returns (LiquiPoolHandler, LiquiPoolVault) {
        vm.startBroadcast();

        // 1. Deploy Handler
        LiquiPoolHandler poolHandler = new LiquiPoolHandler(
            POOL_MANAGER,
            MONTHLY_CONTRIBUTION,
            SECURITY_DEPOSIT,
            GRACE_PENALTY_FEE,
            PRIMARY_WINDOW_DURATION,
            GRACE_PERIOD_DURATION
        );
        console.log("LiquiPoolHandler deployed at :", address(poolHandler));

        // 2. Deploy Vault with only Handler address
        LiquiPoolVault vaultContract = new LiquiPoolVault(address(poolHandler));
        console.log("LiquiPoolVault deployed at   :", address(vaultContract));

        // 3. Wire Vault address back into Handler
        poolHandler.updateVaultContractAddress(address(vaultContract));
        console.log("Vault address registered in Handler");

        vm.stopBroadcast();

        return (poolHandler, vaultContract);
    }
}