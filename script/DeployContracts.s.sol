// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Script, console } from "forge-std/Script.sol";
import { LiquiPoolHandler } from "../src/LiquiPool.sol";
import { LiquiPoolVault } from "../src/LiquiPoolVault.sol";
import { MockUSDT } from "../src/MockUSDT.sol";
import { LiquiPoolRandom } from "../src/LiquiPoolRandom.sol";
import {
    VRFCoordinatorV2_5Mock
} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract DeployContracts is Script {

    address constant POOL_MANAGER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    uint96 private baseFee = 0.25 ether;
    uint96 private gasPrice = 1e9;
    int256 private weiPerUnitLink = 4e15;

    uint256 constant MONTHLY_CONTRIBUTION    = 0.01 ether;
    uint256 constant SECURITY_DEPOSIT        = 0.1 ether;
    uint256 constant GRACE_PENALTY_FEE       = 0.001 ether;

    uint256 constant PRIMARY_WINDOW_DURATION = 420;
    uint256 constant GRACE_PERIOD_DURATION   = 240;

    // 🔹 VRF CONFIG (use real values on testnet/mainnet)
    address public VRF_COORDINATOR = address(0); // set real
    bytes32 constant KEY_HASH = 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae;        // set real
    uint256 public SUB_ID = 0;                   // set real
    uint32 constant CALLBACK_GAS_LIMIT = 500_000;

    function run() external returns (LiquiPoolHandler, LiquiPoolVault) {
        vm.startBroadcast();
 
            VRFCoordinatorV2_5Mock mock = new VRFCoordinatorV2_5Mock(baseFee, gasPrice, weiPerUnitLink);
            VRF_COORDINATOR = address(mock);

            SUB_ID = VRFCoordinatorV2_5Mock(VRF_COORDINATOR).createSubscription();
            VRFCoordinatorV2_5Mock(VRF_COORDINATOR).fundSubscription(SUB_ID, 1000 ether);
    

        MockUSDT poolToken = new MockUSDT();

        // 1. Deploy Handler
        LiquiPoolHandler poolHandler = new LiquiPoolHandler(
            POOL_MANAGER,
            MONTHLY_CONTRIBUTION,
            SECURITY_DEPOSIT,
            GRACE_PENALTY_FEE,
            PRIMARY_WINDOW_DURATION,
            GRACE_PERIOD_DURATION
        );

        console.log("Handler:", address(poolHandler));

        // 2. Deploy Vault
        LiquiPoolVault vaultContract = new LiquiPoolVault(
            address(poolHandler),
            address(poolToken)
        );

        console.log("Vault:", address(vaultContract));

        // 3. Deploy Random (PASS VAULT + VRF PARAMS)
        LiquiPoolRandom randomContract = new LiquiPoolRandom(
            VRF_COORDINATOR,
            KEY_HASH,
            SUB_ID,
            CALLBACK_GAS_LIMIT,
            address(vaultContract)   // 🔥 IMPORTANT
        );

        VRFCoordinatorV2_5Mock(VRF_COORDINATOR).addConsumer(SUB_ID, address(randomContract));

        console.log("Random:", address(randomContract));

        // 4. Wire Vault into Handler
        poolHandler.updateVaultContractAddress(address(vaultContract));

        // 5. Register Random in Vault
        vaultContract.registerPoolRandom(address(randomContract));

        console.log("Random registered in Vault");

        vm.stopBroadcast();

        return (poolHandler, vaultContract);
    }
}