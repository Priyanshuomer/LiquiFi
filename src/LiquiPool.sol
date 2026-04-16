// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;


contract LiquiPoolHandler {
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


    constructor(
        address _poolManager, 
        uint256 _perPersonContributionPerMonth,
        uint256 _poolMakerSecurityDeposit
    ) {
        s_poolState = LiquiPoolState.OPEN;
        s_poolManager = _poolManager;
        i_owner = msg.sender;
        s_perPersonContributionPerMonth = _perPersonContributionPerMonth;
        s_poolMakerSecurityDeposit = _poolMakerSecurityDeposit;
        
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

    function getPoolMakerSecurityDeposit() public view returns(uint256) {
        return s_poolMakerSecurityDeposit;
    }

    function getPoolState() public view returns(LiquiPoolState) {
        return s_poolState;
    }

    function getWhetherPlayerIsAllowedOrNot(address player) public view returns(bool) {
        return s_isAllowed[player];
    }

    function getAllowedPlayers() public view returns(address[] memory) {
        return s_allowedPlayers;
    }
}
