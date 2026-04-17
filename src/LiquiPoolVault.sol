// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {LiquiPoolHandler} from "./LiquiPool.sol";

contract LiquiPoolVault {
    /**
     * ERRORS
     */
    error LiquiPoolVault__NotEnoughSecurityDeposit();
    error LiquiPoolVault__IsNotClosed();
    error LiquiPoolVault__IsNotOpen();
    error LiquiPoolVault__OnlyPoolManager();
    error LiquiPoolVault__TransferFailed();
    error LiquiPoolVault__NotEnoughMonthlyDeposit();
    error LiquiPoolVault__AlreadyContributedThisMonth();
    error LiquiPoolVault__PlayerIsNotAllowed();
    error LiquiPoolVault__NotEnoughSecurityDepositToRelease();
    error LiquiPoolVault__BidWindowIsNotOpen();
    error LiquiPoolVault__NotEnoughBidAmount();
    error LiquiPoolVault__AlreadyWonBid();
    error LiquiPoolVault__BidWindowIsOpen();
    error LiquiPoolVault__AllMonthsCompleted();
    error LiquiPoolVault__IsNotRunning();
    error LiquiPoolVault__IsRunning();
    error LiquiPoolVault__NotDistributedThisMonth();
    error LiquiPoolVault__NotAllMonthsCompleted();
    error LiquiPoolVault__NoWinnersDeclaredYet();
    error LiquiPoolVault__NotContributedThisMonth(address player);

    /**
     * EVENTS
     */
    event SecurityMoneyReleased();
    event MonthlyDepositSubmitted(address indexed player);
    event SecurityMoneyDeposited();
    event PoolIsReset();
    event MonthlyContributionStatusReset();
    event newBidPlaced(address indexed bidder, uint256 indexed _bidAmount);
    event MonthlyContributionDistributed();

    /*** MODIFIERS  */

    modifier onlyPoolMaker() {
        if (msg.sender != poolHandler.s_poolManager()) {
            revert LiquiPoolVault__OnlyPoolManager();
        }
        _;
    }

    modifier isBidWindowOpen() {
        if (s_isBidWindowOpen == false) {
            revert LiquiPoolVault__BidWindowIsNotOpen();
        }

        _;
    }

    modifier isBidWindowClosed() {
        if (s_isBidWindowOpen == true) {
            revert LiquiPoolVault__BidWindowIsOpen();
        }

        _;
    }

    modifier isDrawRunning() {
        if (poolHandler.getPoolState() != LiquiPoolHandler.LiquiPoolState.RUNNING) {
            revert LiquiPoolVault__IsNotRunning();
        }
        _;
    }

    modifier isDrawNotRunning() {
        if (poolHandler.getPoolState() == LiquiPoolHandler.LiquiPoolState.RUNNING) {
            revert LiquiPoolVault__IsRunning();
        }
        _;
    }

    modifier IsAllMonthsCompleted() {
        if (s_holderOfEachMonth.length < poolHandler.getEnrolledMembers().length) {
            revert LiquiPoolVault__NotAllMonthsCompleted();
        }
        _;
    }

    modifier IsNotAllMonthsCompleted() {
        if (s_holderOfEachMonth.length >= poolHandler.getEnrolledMembers().length) {
            revert LiquiPoolVault__AllMonthsCompleted();
        }
        _;
    }

    /**
     * STATE VARIABLES
     */
    LiquiPoolHandler private poolHandler;
    bool private s_isSecurityDepositSubmitted;
    uint256 private s_securityDeposit;
    address[] public s_holderOfEachMonth; // who won the bid every month
    mapping(address => bool) private s_isWinnerOfAnyMonth; // to check whether the player has won any month or not

    mapping(address => bool) private s_hasContributedThisMonth;

    address public s_currentMaxBidder;
    uint256 public s_currentMaxBid;
    address[] public s_remainingPlayers;

    bool public s_isBidWindowOpen;
    bool public s_isThisMonthDistributed;

    constructor(address _poolHandler) {
        poolHandler = LiquiPoolHandler(_poolHandler);
        s_isSecurityDepositSubmitted = false;
        s_remainingPlayers = poolHandler.getEnrolledMembers();
        s_currentMaxBid = poolHandler.getPerPersonContributionPerMonth() * poolHandler.getEnrolledMembers().length;
        s_currentMaxBidder = address(0);
        s_isBidWindowOpen = false;
        s_isThisMonthDistributed = false;
    }

    /**
     * Pool Manager Functions
     */
    function submitSecurityDeposit() public payable onlyPoolMaker {
        if (msg.value < poolHandler.getPoolMakerSecurityDeposit()) {
            revert LiquiPoolVault__NotEnoughSecurityDeposit();
        }

        if (s_isSecurityDepositSubmitted == false) {
            s_isSecurityDepositSubmitted = true;
        }

        s_securityDeposit += msg.value;
        emit SecurityMoneyDeposited();
    }

    function releaseSecurityDeposit() public payable onlyPoolMaker isDrawNotRunning IsAllMonthsCompleted {
        if (s_securityDeposit <= 0) {
            revert LiquiPoolVault__NotEnoughSecurityDepositToRelease();
        }

        (bool success,) = payable(poolHandler.getPoolManager()).call{value: s_securityDeposit}("");

        if (!success) {
            revert LiquiPoolVault__TransferFailed();
        }

        s_isSecurityDepositSubmitted = false;
        s_securityDeposit = 0;

        emit SecurityMoneyReleased();
    }

    function resetPool() public onlyPoolMaker isDrawNotRunning isBidWindowClosed {
        if (s_isThisMonthDistributed == false) {
            revert LiquiPoolVault__NotDistributedThisMonth();
        }

        for (uint256 i = 0; i < s_holderOfEachMonth.length; i++) {
            s_hasContributedThisMonth[s_holderOfEachMonth[i]] = false;
            s_isWinnerOfAnyMonth[s_holderOfEachMonth[i]] = false;
        }

        delete s_holderOfEachMonth;
        s_securityDeposit = 0;
        s_isSecurityDepositSubmitted = false;
        //  delete poolHandler.s_allowedPlayers();

        emit PoolIsReset();
    }

    function resetMonthlyContributionStatus() public onlyPoolMaker isBidWindowClosed {
        if (s_isThisMonthDistributed == false) {
            revert LiquiPoolVault__NotDistributedThisMonth();
        }

        address[] memory allPlayers = poolHandler.getAllowedPlayers();

        for (uint256 i = 0; i < allPlayers.length; i++) {
            s_hasContributedThisMonth[allPlayers[i]] = false;
        }

        s_isThisMonthDistributed = false;

        emit MonthlyContributionStatusReset();
    }

    function submitMonthlyDepositOnBehalfOfOther(address player)
        public
        payable
        onlyPoolMaker
        isDrawRunning
        isBidWindowClosed
    {
        if (msg.value < poolHandler.getPerPersonContributionPerMonth()) {
            revert LiquiPoolVault__NotEnoughMonthlyDeposit();
        }

        if (poolHandler.getWhetherPlayerIsAllowedOrNot(player) == false) {
            revert LiquiPoolVault__PlayerIsNotAllowed();
        }

        if (s_hasContributedThisMonth[player] == true) {
            revert LiquiPoolVault__AlreadyContributedThisMonth();
        }

        s_hasContributedThisMonth[player] = true;

        emit MonthlyDepositSubmitted(player);
    }

    /**
     * Player's functions
     */
    function contributeMonthly() public payable isDrawRunning isBidWindowClosed {
        if (msg.value < poolHandler.getPerPersonContributionPerMonth()) {
            revert LiquiPoolVault__NotEnoughMonthlyDeposit();
        }

        if (poolHandler.getWhetherPlayerIsAllowedOrNot(msg.sender) == false) {
            revert LiquiPoolVault__PlayerIsNotAllowed();
        }

        if (s_hasContributedThisMonth[msg.sender] == true) {
            revert LiquiPoolVault__AlreadyContributedThisMonth();
        }

        s_hasContributedThisMonth[msg.sender] = true;
        emit MonthlyDepositSubmitted(msg.sender);
    }

    function makeBidForThisMonth(uint256 _bidAmount) public isBidWindowOpen isDrawRunning {
        if (_bidAmount >= s_currentMaxBid) {
            revert LiquiPoolVault__NotEnoughBidAmount();
        }

        if (!poolHandler.getWhetherPlayerIsAllowedOrNot(msg.sender)) {
            revert LiquiPoolVault__PlayerIsNotAllowed();
        }

        if (s_isWinnerOfAnyMonth[msg.sender] == true) {
            revert LiquiPoolVault__AlreadyWonBid();
        }

        if (s_currentMaxBidder != msg.sender) {
            s_currentMaxBidder = msg.sender;
        }

        s_currentMaxBid = _bidAmount;

        emit newBidPlaced(msg.sender, _bidAmount);
    }

    function openBidWindow() public onlyPoolMaker isDrawRunning isBidWindowClosed {
        s_isBidWindowOpen = true;
    }

    function closeBidWindow() public onlyPoolMaker isDrawRunning isBidWindowOpen {
        s_isBidWindowOpen = false;
    }

    function distributeMonthlyDeposit() public payable isBidWindowClosed isDrawRunning IsNotAllMonthsCompleted {
        address[] memory allPlayers = poolHandler.getAllowedPlayers();

        /**
         * Check Whether All Players Have Contributed This Month or Not
         */
        for (uint256 i = 0; i < allPlayers.length; i++) {
            if (s_hasContributedThisMonth[allPlayers[i]] == false) {
                revert LiquiPoolVault__NotContributedThisMonth(allPlayers[i]);
            }
        }

        uint256 totalPoolThisMonth =
            poolHandler.getPerPersonContributionPerMonth() * poolHandler.getAllowedPlayers().length;

        if (s_currentMaxBidder == address(0)) {
            s_currentMaxBid = (totalPoolThisMonth * 95) / 100;
            uint256 randomNumber = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao)))
                % poolHandler.getAllowedPlayers().length;
            s_currentMaxBidder = s_remainingPlayers[randomNumber];
        }

        uint256 amountTranferToBidder = (s_currentMaxBid * 95) / 100;

        uint256 remAmount = totalPoolThisMonth - s_currentMaxBid;

        uint256 amountToBeDistributed = (remAmount * 95) / 100;
        uint256 amountToInvest = totalPoolThisMonth - amountToBeDistributed - amountTranferToBidder;

        uint256 perPersonGet = amountToBeDistributed / poolHandler.getAllowedPlayers().length;

        s_holderOfEachMonth.push(s_currentMaxBidder);

        for (uint256 i = 0; i < s_remainingPlayers.length; i++) {
            if (s_remainingPlayers[i] == s_currentMaxBidder) {
                s_remainingPlayers[i] = s_remainingPlayers[s_remainingPlayers.length - 1];
                s_remainingPlayers.pop();
                break;
            }
        }

        bool success = false;

        /**
         * Distribute
         */
        for (uint256 i = 0; i < allPlayers.length; i++) {
            (success,) = payable(allPlayers[i]).call{value: perPersonGet}("");

            if (!success) {
                revert LiquiPoolVault__TransferFailed();
            }

            amountToBeDistributed -= perPersonGet;
        }

        if (amountToBeDistributed > 0) {
            amountToInvest += amountToBeDistributed;
        }

        (success,) = payable(poolHandler.getPoolManager()).call{value: amountToInvest}("");

        if (!success) {
            revert LiquiPoolVault__TransferFailed();
        }

        (success,) = payable(s_currentMaxBidder).call{value: amountTranferToBidder}("");

        if (!success) {
            revert LiquiPoolVault__TransferFailed();
        }

        s_isThisMonthDistributed = true;
        s_isWinnerOfAnyMonth[s_currentMaxBidder] = true;

        emit MonthlyContributionDistributed();
    }

    /**
     * GETTER FUNCTIONS
     */
    function getAllWinners() public view returns (address[] memory) {
        return s_holderOfEachMonth;
    }

    function getRecentWinner() public view returns (address) {
        if (s_holderOfEachMonth.length == 0) {
            return address(0);
        }

        return s_holderOfEachMonth[s_holderOfEachMonth.length - 1];
    }

    function getWhetherPlayerHasContributedThisMonth(address player) public view returns (bool) {
        if (poolHandler.getWhetherPlayerIsAllowedOrNot(player) == false) {
            revert LiquiPoolVault__PlayerIsNotAllowed();
        }
        return s_hasContributedThisMonth[player];
    }

    function getWhetherPlayerIsWinnerOfAnyMonth(address player) public view returns (bool) {
        if (poolHandler.getWhetherPlayerIsAllowedOrNot(player) == false) {
            revert LiquiPoolVault__PlayerIsNotAllowed();
        }

        return s_isWinnerOfAnyMonth[player];
    }

    function getCurrentMaxBid() public view returns (uint256) {
        return s_currentMaxBid;
    }

    function getCurrentMaxBidder() public view returns (address) {
        return s_currentMaxBidder;
    }

    function getWhetherBidWindowIsOpenOrNot() public view returns (bool) {
        return s_isBidWindowOpen;
    }

    function getWhetherThisMonthDistributedOrNot() public view returns (bool) {
        return s_isThisMonthDistributed;
    }

    function getWhetherSecurityDepositSubmittedOrNot() public view returns (bool) {
        return s_isSecurityDepositSubmitted;
    }

    function getSecurityDepositAmount() public view returns (uint256) {
        return s_securityDeposit;
    }

    function getRemainingPlayers() public view returns (address[] memory) {
        return s_remainingPlayers;
    }

    function getListOfAllPlayersNotContributed() public view returns (address[] memory) {
        address[] memory allPlayers = poolHandler.getAllowedPlayers();
        address[] memory notContributedPlayers = new address[](allPlayers.length);
        uint256 count = 0;

        for (uint256 i = 0; i < allPlayers.length; i++) {
            if (s_hasContributedThisMonth[allPlayers[i]] == false) {
                notContributedPlayers[count] = allPlayers[i];
                count++;
            }
        }

        // Resize the array to fit the number of not contributed players
        assembly {
            mstore(notContributedPlayers, count)
        }

        return notContributedPlayers;
    }

    function getListOfAllPlayersContributed() public view returns (address[] memory) {
        address[] memory allPlayers = poolHandler.getAllowedPlayers();
        address[] memory contributedPlayers = new address[](allPlayers.length);
        uint256 count = 0;

        for (uint256 i = 0; i < allPlayers.length; i++) {
            if (s_hasContributedThisMonth[allPlayers[i]] == true) {
                contributedPlayers[count] = allPlayers[i];
                count++;
            }
        }

        // Resize the array to fit the number of not contributed players
        assembly {
            mstore(contributedPlayers, count)
        }

        return contributedPlayers;
    }
}
