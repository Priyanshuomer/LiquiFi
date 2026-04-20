// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;


import {
    VRFConsumerBaseV2Plus
} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {
    VRFV2PlusClient
} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
 
 import { LiquiPoolVault } from "./LiquiPoolVault.sol";


/**
 * @title LiquiPoolRandom
 * @notice Handles all Chainlink VRF randomness requests for the PoolForge protocol.
 * @dev Deployed separately from LiquiPoolVault to keep contract sizes under the 24KB limit.
 *      Only the registered Vault contract can request randomness.
 *      Vault reads the result after fulfillment via getRandomResult().
 */
contract LiquiPoolRandom is VRFConsumerBaseV2Plus {

    /*** ERRORS  */

    /// @notice Thrown when a non-vault address tries to request randomness
    error LiquiPoolRandom__OnlyVault();


    /// @notice Thrown when reading a request that does not exist
    error LiquiPoolRandom__RequestNotFound(uint256 requestId);

    /// @notice Thrown when reading a request that has not been fulfilled yet
    error LiquiPoolRandom__RequestNotFulfilledYet(uint256 requestId);


   /****  EVENTS  */

    /// @notice Emitted when a randomness request is sent to Chainlink
    event RandomnessRequested(uint256 indexed requestId, uint256 round);

    /// @notice Emitted when Chainlink fulfills a randomness request
    event RandomnessFulfilled(uint256 indexed requestId, uint256 randomWord);
 

    /** TYPES */

    struct RandomRequest {
        uint256 round;        // which pool round this request belongs to
        uint256 randomWord;   // the random word returned by Chainlink
        bool    fulfilled;    // whether Chainlink has responded
        bool    exists;       // whether this requestId was created by us
    }


     /**  STATE VARIABLES */

    /// @notice LiquiPoolVault — only this can request randomness
    LiquiPoolVault private immutable i_vaultContract;

    /// @notice VRF configuration
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subId;
    uint32  private immutable i_callbackGasLimit;
    uint16  private constant  REQUEST_CONFIRMATIONS = 4;
    uint32  private constant  NUM_WORDS             = 1;

    /// @notice Maps requestId to its RandomRequest data
    mapping(uint256 => RandomRequest) private s_requests;

    /// @notice The most recent requestId — used by Vault to read latest result
    uint256 private s_lastRequestId;


    /** CONSTRUCTOR */

    /**
     * @param _vrfCoordinator    Chainlink VRF coordinator address
     * @param _keyHash           Gas lane key hash
     * @param _subId             Chainlink subscription ID
     * @param _callbackGasLimit  Gas limit for fulfillRandomWords callback
     */
    constructor(
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint256 _subId,
        uint32  _callbackGasLimit,
        address _vaultContract
    ) VRFConsumerBaseV2Plus(_vrfCoordinator) {
        i_keyHash           = _keyHash;
        i_subId             = _subId;
        i_callbackGasLimit  = _callbackGasLimit;
        i_vaultContract      = LiquiPoolVault(_vaultContract);
    }


   /** MODIFIERS */

    modifier onlyVault() {
        if (msg.sender != address(i_vaultContract)) revert LiquiPoolRandom__OnlyVault();
        _;
    }

 


   /** VRF FUNCTIONS */

    /**
     * @notice Vault calls this when no bid is placed and a random winner must be selected.
     * @dev Only callable by the registered Vault contract.
     * @param round The current pool round number — stored with the request for traceability
     * @return requestId The Chainlink VRF request ID
     */
    function requestRandom(uint256 round) external onlyVault returns (uint256 requestId) {
        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash:            i_keyHash,
                subId:              i_subId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit:   i_callbackGasLimit,
                numWords:           NUM_WORDS,
                extraArgs:          VRFV2PlusClient._argsToBytes(
                                        VRFV2PlusClient.ExtraArgsV1({ nativePayment: false })
                                    )
            })
        );

        s_requests[requestId] = RandomRequest({
            round:      round,
            randomWord: 0,
            fulfilled:  false,
            exists:     true
        });

        s_lastRequestId = requestId;
        emit RandomnessRequested(requestId, round);
    }

    /**
     * @notice Chainlink VRF coordinator calls this with the random result.
     * @dev Internal — cannot be called externally.
     */
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] calldata randomWords
    ) internal override {
        if (!s_requests[requestId].exists) {
            revert LiquiPoolRandom__RequestNotFound(requestId);
        }

        s_requests[requestId].fulfilled  = true;
        s_requests[requestId].randomWord = randomWords[0];

        i_vaultContract.memberIsRandomlySelected(randomWords[0]);

        emit RandomnessFulfilled(requestId, randomWords[0]);
    }


   /** GETTER FUNCTIONS */

    /**
     * @notice Returns the random word for a specific request.
     * @dev Vault calls this after fulfillment to get the number for winner selection.
     * @param requestId The VRF request ID to read
     * @return The raw random uint256 returned by Chainlink
     */
    function getRandomResult(uint256 requestId) external view returns (uint256) {
        if (!s_requests[requestId].exists) {
            revert LiquiPoolRandom__RequestNotFound(requestId);
        }
        if (!s_requests[requestId].fulfilled) {
            revert LiquiPoolRandom__RequestNotFulfilledYet(requestId);
        }
        return s_requests[requestId].randomWord;
    }

    /// @notice Returns whether a request has been fulfilled
    function isRequestFulfilled(uint256 requestId) external view returns (bool) {
        return s_requests[requestId].fulfilled;
    }

    /// @notice Returns the most recent VRF request ID
    function getLastRequestId() external view returns (uint256) {
        return s_lastRequestId;
    }

    /// @notice Returns the registered vault address
    function getVaultAddress() external view returns (address) {
        return address(i_vaultContract);
    }
}
