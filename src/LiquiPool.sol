// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {
    VRFConsumerBaseV2Plus
} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {
    VRFV2PlusClient
} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

contract LiquiPoolHandler is VRFConsumerBaseV2Plus {
    /**
     * ERRORS
     */
    error LiquiPool__NotOpenToEnter();
    error LiquiPool__OnlyOwner();
    error LiquiPool__OnlyPoolManager();
    error LiquiPool__AlreadyAllowedToEnter();
    error LiquiPool__NotRunning();
    error LiquiPool__AlreadyDisallowedToEnter();

    /**
     * EVENTS
     */
    event SubmitRequestToEnter(address indexed requester);
    event AlreadyAllowedToEnter(address indexed requester);
    event PlayerIsAllowed(address indexed requester);
    event PoolManagerChanged(address indexed newPoolManager);
    event PlayerRemovedFromPool(address indexed requester);

    enum LiquiPoolState {
        OPEN,
        CLOSED,
        BLOCKED,
        RUNNING
    }

    /**
     * STATE VARIABLES
     */
    LiquiPoolState private s_poolState;
    mapping(address => bool) private s_isAllowed;
    address public immutable i_owner;
    address public s_poolManager;
    address[] public s_allowedPlayers;
    uint256 public s_perPersonContributionPerMonth;
    uint256 public s_poolMakerSecurityDeposit;

    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subId;
    uint32 private immutable i_callbackGasLimit;

    uint16 private immutable REQUEST_CONFIRMATIONS = 4;

    constructor(
        address _poolManager,
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint256 _subId,
        uint32 _callbackGasLimit,
        uint256 _perPersonContributionPerMonth,
        uint256 _poolMakerSecurityDeposit
    ) VRFConsumerBaseV2Plus(_vrfCoordinator) {
        s_poolState = LiquiPoolState.OPEN;
        s_poolManager = _poolManager;
        i_owner = msg.sender;
        s_perPersonContributionPerMonth = _perPersonContributionPerMonth;
        s_poolMakerSecurityDeposit = _poolMakerSecurityDeposit;
        i_keyHash = _keyHash;
        i_callbackGasLimit = _callbackGasLimit;
        i_subId = _subId;
    }

    /**
     * MODIFIERS
     */
    modifier isDrawRunning() {
        if (s_poolState != LiquiPoolState.RUNNING) {
            revert LiquiPool__NotRunning();
        }
        _;
    }

    modifier isPoolOpenToEnter() {
        if (s_poolState != LiquiPoolState.OPEN) {
            revert LiquiPool__NotOpenToEnter();
        }
        _;
    }

    modifier isOwner() {
        if (msg.sender != i_owner) {
            revert LiquiPool__OnlyOwner();
        }
        _;
    }

    modifier onlyPoolManager() {
        if (msg.sender != s_poolManager) {
            revert LiquiPool__OnlyPoolManager();
        }
        _;
    }

    function submitRequestToEnter() public isPoolOpenToEnter {
        if (s_isAllowed[msg.sender]) {
            revert LiquiPool__AlreadyAllowedToEnter();
        }

        s_isAllowed[msg.sender] = false;
        emit SubmitRequestToEnter(msg.sender);
    }

    function approveRequestToEnter(address requester) public onlyPoolManager {
        if (s_isAllowed[requester]) {
            revert LiquiPool__AlreadyAllowedToEnter();
        }

        s_isAllowed[requester] = true;
        s_allowedPlayers.push(requester);
        emit PlayerIsAllowed(requester);
    }

    function removePlayerFromPool(address requester) public onlyPoolManager {
        if (!s_isAllowed[requester]) {
            revert LiquiPool__AlreadyDisallowedToEnter();
        }

        s_isAllowed[requester] = false;
        for (uint256 i = 0; i < s_allowedPlayers.length; i++) {
            if (s_allowedPlayers[i] == requester) {
                s_allowedPlayers[i] = s_allowedPlayers[s_allowedPlayers.length - 1];
                s_allowedPlayers.pop();
                break;
            }
        }

        emit PlayerRemovedFromPool(requester);
    }


    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override{

    }

    /**
     * OWNER ONLY FUNCTIONS
     */

    function changePoolManager(address _newPoolManager) public isOwner {
        s_poolManager = _newPoolManager;
        emit PoolManagerChanged(_newPoolManager);
    }


    /** GETTER FUNCTIONS */

    function getPoolManager() public view returns(address) {
         return s_poolManager;
    }

    function getPerPersonContributionPerMonth() public view returns(uint256) {
        return s_perPersonContributionPerMonth;
    }
}
