// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { LiquiPoolHandler } from "./LiquiPool.sol";

/**
 * @title LiquiPoolVault
 * @notice Financial custody and settlement layer for the LiquiPool decentralized protocol.
 * @dev Handles all monetary operations — security deposits, monthly contributions, bidding rounds,
 *      payout settlement, and member reputation scoring.
 *      LiquiPoolHandler.sol must be deployed first. Pass its address into this constructor.
 *      This contract is the only entity that moves funds. LiquiPoolHandler never holds any funds.
 */
contract LiquiPoolVault {

   /*** ERRORS  */
    /// @notice Thrown when a non-pool-manager calls a manager-restricted function
    error LiquiPoolVault__OnlyPoolManager();

    error LiquiPoolVault__ContributionWindowClosed();

    /// @notice Thrown when fund transfer to a recipient fails
    error LiquiPoolVault__TransferFailed(address recipient, uint256 amount);

    /// @notice Thrown when submitted security deposit is below the required amount
    error LiquiPoolVault__InsufficientSecurityDeposit();

    /// @notice Thrown when there is no security deposit balance to release
    error LiquiPoolVault__NoSecurityDepositToRelease();

    /// @notice Thrown when submitted monthly contribution is below the required amount
    error LiquiPoolVault__InsufficientContribution(uint256 sendingAmount, uint256 requiredAmount);

   /// @notice Thrown when there is no sufficient security deposit to contribute on behalf of defaulter 
    error LiquiPoolVault__NotEnoughSecurityBalanceToContribute(address defaulter);

    /// @notice Thrown when a member tries to contribute more than once in the same round
    error LiquiPoolVault__ContributionAlreadySubmitted();

    /// @notice Thrown when an address that is not an enrolled member attempts a member action
    error LiquiPoolVault__CallerIsNotEnrolledMember();

    /// @notice Thrown when a function requires the bidding round to be active but it is not
    error LiquiPoolVault__BiddingRoundNotActive();

    /// @notice Thrown when a function requires the bidding round to be closed but it is open
    error LiquiPoolVault__BiddingRoundCurrentlyActive();

    /// @notice Thrown when a submitted bid is not lower than the current lowest bid
    error LiquiPoolVault__BidNotLowerThanCurrentLowest();

    /// @notice Thrown when a member who has already received a payout attempts to bid
    error LiquiPoolVault__MemberAlreadyReceivedPayout();

    /// @notice Thrown when a function requires the pool to be ACTIVE but it is not
    error LiquiPoolVault__PoolNotActive();

    /// @notice Thrown when a function requires the pool to NOT be ACTIVE but it is
    error LiquiPoolVault__PoolCurrentlyActive();

    /// @notice Thrown when settlement is attempted but not all rounds have been completed
    error LiquiPoolVault__NotAllRoundsCompleted();

    /// @notice Thrown when an action is attempted after all rounds are already completed
    error LiquiPoolVault__AllRoundsAlreadyCompleted();

    /// @notice Thrown when settlement is attempted before the current round is distributed
    error LiquiPoolVault__CurrentRoundNotYetSettled();

    /// @notice Thrown when a member has not contributed in the current round
    error LiquiPoolVault__MemberHasNotContributed(address member);

    /// @notice Thrown when pool manager tries to finalize without settling current round first
    error LiquiPoolVault__UnsettledRoundExists();


    /*** EVENTS */

    /// @notice Emitted when the pool manager successfully locks the security deposit
    event SecurityDepositLocked(address indexed poolManager, uint256 amount);

    /// @notice Emitted when the security deposit is returned to the pool manager
    event SecurityDepositReleased(address indexed poolManager, uint256 amount);

    /// @notice Emitted when a member successfully submits their monthly contribution
    event ContributionReceived(address indexed member, uint256 round, uint256 amount);

    /// @notice Emitted when a new lowest bid is placed during an active bidding round
    event BidSubmitted(address indexed bidder, uint256 bidAmount, uint256 round);

    /// @notice Emitted when the pool manager opens the monthly bidding round
    event BiddingRoundOpened(uint256 round);

    /// @notice Emitted when the pool manager closes the monthly bidding round
    event BiddingRoundClosed(uint256 round);

    /// @notice Emitted when the round is settled and funds are distributed
    event RoundSettled(address indexed roundWinner, uint256 payoutAmount, uint256 round);

    /// @notice Emitted when the pool manager covers a defaulting member's contribution
    event DefaultCoveredByPoolManager(address indexed defaultedMember, uint256 amount, uint256 round);

    /// @notice Emitted when the pool vault contract covers a defaulting member's contribution via security deposit 
    event DefaultCoveredByPoolVault(address indexed defaultedMember, uint256 amount, uint256 round);

    /// @notice Emitted when monthly contribution statuses are reset for the next round
    event NextRoundPrepared(uint256 newRound);

    /// @notice Emitted when the full pool cycle is finalized and reset
    event PoolCycleFinalized();

 




    /*** STATE VARIABLES  */
    // ── Protocol references ──────────────────────
    /// @notice Reference to the handler contract for member and state lookups
    LiquiPoolHandler private immutable i_poolHandler;


    // ── Round tracking ───────────────────────────
    /// @notice Current round number (1-indexed, increments after each settlement)
    uint256 private s_currentRound;

    /// @notice Ordered list of addresses that have received their payout, one per round
    address[] private s_roundWinners;

    /// @notice Maps member address to whether they have received a payout in any round for quick access
    mapping(address => bool) private s_hasReceivedPayout;

    /// @notice Tracks which members have contributed in the current round
    mapping(address => bool) private s_hasContributedThisRound;

    /// @notice Whether the current round's funds have been settled and distributed
    bool private s_isCurrentRoundSettled;

    // ── Eligible bidders ─────────────────────────
    /// @notice Members who have not yet received a payout — eligible to bid each round
    address[] private s_eligibleBidders;

    /// @notice Whether eligible bidders list has been initialized from handler
    bool private s_eligibleBiddersInitialized;

    // ── Bidding round state ──────────────────────
    /// @notice Whether the bidding round is currently open for submissions
    bool private s_isBiddingRoundActive;

    /// @notice The lowest bid placed so far in the current round
    uint256 private s_currentLowestBid;

    /// @notice Address of the member who placed the current lowest bid
    address private s_currentLowestBidder;


    /// @notice Tracks whether a member contributed during grace period this round
    mapping(address => bool) private s_contributedDuringGracePeriod;
    
    /// @notice Timestamp when the current round's primary contribution window opened
    uint256 private s_roundContributionWindowStart;
    


   /**  CONSTRUCTOR   */

    /**
     * @param _poolHandler                 Address of the deployed LiquiPoolHandler contract
     */
    constructor(
        address _poolHandler
    ) {
        i_poolHandler                = LiquiPoolHandler(_poolHandler);
       
        s_currentRound               = 0;
        s_isBiddingRoundActive       = false;
        s_isCurrentRoundSettled      = true;
    }


   /***  MODIFIERS  */

    /// @dev Restricts function to the pool manager only
    modifier onlyPoolManager() {
        if (msg.sender != i_poolHandler.getPoolManager()) {
            revert LiquiPoolVault__OnlyPoolManager();
        }
        _;
    }

    /// @dev Requires the pool to be in ACTIVE state in the handler
    modifier onlyWhenPoolActive() {
        if (i_poolHandler.getPoolState() != LiquiPoolHandler.PoolState.ACTIVE) {
            revert LiquiPoolVault__PoolNotActive();
        }
        _;
    }

    /// @dev Requires the pool to NOT be in ACTIVE state
    modifier onlyWhenPoolNotActive() {
        if (i_poolHandler.getPoolState() == LiquiPoolHandler.PoolState.ACTIVE) {
            revert LiquiPoolVault__PoolCurrentlyActive();
        }
        _;
    }

    /// @dev Requires the bidding round to currently be open
    modifier onlyWhenBiddingActive() {
        if (!s_isBiddingRoundActive) {
            revert LiquiPoolVault__BiddingRoundNotActive();
        }
        _;
    }

    /// @dev Requires the bidding round to currently be closed
    modifier onlyWhenBiddingClosed() {
        if (s_isBiddingRoundActive) {
            revert LiquiPoolVault__BiddingRoundCurrentlyActive();
        }
        _;
    }

    /// @dev Requires all rounds to be completed (cycle finished)
    modifier onlyWhenAllRoundsCompleted() {
        if (s_roundWinners.length < i_poolHandler.getEnrolledMemberCount()) {
            revert LiquiPoolVault__NotAllRoundsCompleted();
        }
        _;
    }

    /// @dev Requires NOT all rounds to be completed yet
    modifier onlyWhenRoundsRemaining() {
        if (s_roundWinners.length >= i_poolHandler.getEnrolledMemberCount()) {
            revert LiquiPoolVault__AllRoundsAlreadyCompleted();
        }
        _;
    }


  

    /***   POOL MANAGER — SECURITY DEPOSIT   */

    /**
     * @notice Pool manager locks the required security deposit before the pool can be activated.
     * @dev The Vault must hold this deposit for the entire cycle duration.
     *      Pool manager calls this, then calls activatePool() on the Handler.
     *      Allows top-ups if the deposit was partially used to cover defaults.
     */
    function lockSecurityDeposit() public payable onlyPoolManager {
        if (msg.value < i_poolHandler.getRequiredSecurityDeposit()) {
            revert LiquiPoolVault__InsufficientSecurityDeposit();
        }
        i_poolHandler.recordSecurityDepositLocked(msg.value);
        emit SecurityDepositLocked(msg.sender, msg.value);
    }

    /**
     * @notice Returns the remaining security deposit to the pool manager after the full cycle ends.
     * @dev Only callable after all rounds are completed and pool is no longer ACTIVE.
     *      If defaults were covered, the returned amount may be less than the original deposit.
     */
    function releaseSecurityDeposit()
        public
        onlyWhenPoolNotActive
        onlyWhenAllRoundsCompleted
    {
        uint256 amount = i_poolHandler.getRequiredSecurityDeposit();
        if (amount == 0) {
            revert LiquiPoolVault__NoSecurityDepositToRelease();
        }
 
        i_poolHandler.recordSecurityDepositReleased();

        (bool success, ) = payable(i_poolHandler.getPoolManager()).call{value: amount}("");
        if (!success) revert LiquiPoolVault__TransferFailed(i_poolHandler.getPoolManager(), amount);

        emit SecurityDepositReleased(msg.sender, amount);
    }


   /***  POOL MANAGER — ROUND MANAGEMENT  */

    /**
     * @notice Opens the bidding round for the current month.
     *         Members may now submit bids until the pool manager closes the round.
     * @dev Initializes the eligible bidders list on the first round from the Handler's
     *      enrolled members. Resets the lowest bid ceiling to the full pool value.
     */
    function openBiddingRound()
        public
        onlyPoolManager
        onlyWhenPoolActive
        onlyWhenBiddingClosed
        onlyWhenRoundsRemaining
    {
        if (!s_eligibleBiddersInitialized) {
            s_eligibleBidders            = i_poolHandler.getEnrolledMembers();
            s_eligibleBiddersInitialized = true;
        }

        uint256 totalPool        = i_poolHandler.getMonthlyContributionAmount() * i_poolHandler.getEnrolledMemberCount();
        s_currentLowestBid       = totalPool;
        s_currentLowestBidder    = address(0);
        s_isBiddingRoundActive   = true;
        s_isCurrentRoundSettled  = false;
        s_roundContributionWindowStart = block.timestamp;

        emit BiddingRoundOpened(s_currentRound + 1);
    }

    /**
     * @notice Closes the active bidding round. No further bids are accepted after this.
     * @dev Settlement via settleCurrentRound() must be called separately after this.
     */
    function closeBiddingRound()
        public
        onlyPoolManager
        onlyWhenPoolActive
        onlyWhenBiddingActive
    {
        if(s_isBiddingRoundActive)
        s_isBiddingRoundActive = false;

        emit BiddingRoundClosed(s_currentRound + 1);
    }

    /**
     * @notice Pool manager's security deposit covers a defaulting member's contribution using the security deposit.
     *         Protects pool continuity — the round proceeds as if the member paid.
     * @dev Deducts from security deposit balance and marks the member as having contributed.
     *      Applies a heavy score penalty to the defaulting member.
     * @param defaultingMember Address of the member who failed to contribute
     */
    function _coverMemberDefault(address defaultingMember)
        internal
        onlyWhenPoolActive
        onlyWhenBiddingClosed
    {
        if (!i_poolHandler.isMemberEnrolled(defaultingMember)) {
            revert LiquiPoolVault__CallerIsNotEnrolledMember();
        }

        if (s_hasContributedThisRound[defaultingMember]) {
            revert LiquiPoolVault__ContributionAlreadySubmitted();
        }

        uint256 _monthlyContribution = i_poolHandler.getMonthlyContributionAmount();

        if(i_poolHandler.getSecurityDepositBalance() < _monthlyContribution)
          revert LiquiPoolVault__NotEnoughSecurityBalanceToContribute(defaultingMember);

        i_poolHandler.deductFromSecurityDeposit(_monthlyContribution);
        s_hasContributedThisRound[defaultingMember] = true;

       (, , , , , , , uint256 penaltyDefault) = i_poolHandler.getScoreConstants();
      i_poolHandler.decreaseScore(defaultingMember, penaltyDefault);

        emit DefaultCoveredByPoolVault(defaultingMember, _monthlyContribution, s_currentRound + 1);
    }


    /**
     * @notice Resets contribution statuses and prepares the contract state for the next round.
     * @dev Must be called after settleCurrentRound(). Increments the round counter.
     *      Clears per-round contribution flags for all enrolled members.
     */
    function prepareNextRound()
        public
        onlyPoolManager
        onlyWhenBiddingClosed
    {
        if (!s_isCurrentRoundSettled) {
            revert LiquiPoolVault__CurrentRoundNotYetSettled();
        }

        address[] memory members = i_poolHandler.getEnrolledMembers();
        for (uint256 i = 0; i < members.length; i++) {
            s_hasContributedThisRound[members[i]]       = false;
            s_contributedDuringGracePeriod[members[i]]  = false;
        }

        s_currentRound++;
        s_currentLowestBid    = 0;
        s_currentLowestBidder = address(0);

        emit NextRoundPrepared(s_currentRound);
    }

    /**
     * @notice Finalizes the full pool cycle. Resets all cycle-level state.
     * @dev Only callable after all rounds are complete and current round is settled.
     *      Does not release the security deposit — pool manager calls releaseSecurityDeposit() separately.
     */
    function finalizePoolCycle()
        public
        onlyPoolManager
        onlyWhenPoolNotActive
        onlyWhenAllRoundsCompleted
    {
        if (!s_isCurrentRoundSettled) {
            revert LiquiPoolVault__UnsettledRoundExists();
        }

        address[] memory members = i_poolHandler.getEnrolledMembers();

        for (uint256 i = 0; i < members.length; i++) {
            s_hasContributedThisRound[members[i]]      = false;
            s_hasReceivedPayout[members[i]]            = false;
            s_contributedDuringGracePeriod[members[i]] = false;
        }

        delete s_roundWinners;
        delete s_eligibleBidders;

        s_currentRound              = 0;
        s_eligibleBiddersInitialized = false;
        s_isCurrentRoundSettled      = true;

        emit PoolCycleFinalized();
    }


  /***   POOL MANAGER — SUBMIT ON BEHALF OF DEFAULTING MEMBER   */

    /**
     * @notice Pool manager submits a monthly contribution on behalf of another member.
     * @dev Used when the pool manager chooses to fund a member externally rather than
     *      drawing from the security deposit. Score penalty still applies.
     * @param member Address of the member on whose behalf the contribution is made
     */
    function submitContributionOnBehalfOf(address member)
        public
        payable
        onlyPoolManager
        onlyWhenPoolActive
        onlyWhenBiddingClosed
    {
        if (!i_poolHandler.isMemberEnrolled(member)) {
            revert LiquiPoolVault__CallerIsNotEnrolledMember();
        }

        if (s_hasContributedThisRound[member]) {
            revert LiquiPoolVault__ContributionAlreadySubmitted();
        }

        uint256 _monthlyContribution = i_poolHandler.getMonthlyContributionAmount();

        if (msg.value < _monthlyContribution) {
            revert LiquiPoolVault__InsufficientContribution(msg.value, _monthlyContribution);
        }


        s_hasContributedThisRound[member] = true;
       (, , , , , , , uint256 penaltyDefault) = i_poolHandler.getScoreConstants();

        i_poolHandler.decreaseScore(member, penaltyDefault);

        emit DefaultCoveredByPoolManager(member, msg.value, s_currentRound + 1);
    }


   /**  MEMBER — CONTRIBUTION  */
    /**
     * @notice Member submits their fixed monthly contribution for the current round.
     * @dev Contribution must equal exactly s_monthlyContributionAmount.
     *      Score is awarded based on whether submission falls within the primary window
     *      or the grace period. Grace period contributions also require an additional
     *      penalty fee forwarded to the pool manager.
     *      Contributing after both windows have closed is not permitted — pool manager
     *      must use coverMemberDefault() instead.
     */

  function contributeMonthly() public payable onlyWhenPoolActive onlyWhenBiddingClosed {
            if (!i_poolHandler.isMemberEnrolled(msg.sender)) {
                revert LiquiPoolVault__CallerIsNotEnrolledMember();
            }
            if (s_hasContributedThisRound[msg.sender]) {
                revert LiquiPoolVault__ContributionAlreadySubmitted();
            }

            uint256 _primaryWindowDuration = i_poolHandler.getPrimaryWindowDuration();

            uint256 _gracePeriodDuration = i_poolHandler.getGracePeriodDuration();

            uint256 _monthlyContribution = i_poolHandler.getMonthlyContributionAmount();

            uint256 elapsed      = block.timestamp - s_roundContributionWindowStart;
            bool inPrimaryWindow = elapsed <= _primaryWindowDuration;
            bool inGracePeriod   = !inPrimaryWindow && elapsed <= (_primaryWindowDuration + _gracePeriodDuration);

            (, , , uint256 timelyControBonus , , , , ) = i_poolHandler.getScoreConstants();

            if (inPrimaryWindow) {
                // On-time — only monthly amount required
                if (msg.value < _monthlyContribution) {
                    revert LiquiPoolVault__InsufficientContribution(msg.value, _monthlyContribution);
                }
                i_poolHandler.increaseScore(msg.sender, timelyControBonus);

            } else if (inGracePeriod) {
                // Late — must send monthly + penalty together
                uint256 _graceFee = i_poolHandler.getGracePeriodPenaltyFee();

                if (msg.value < _monthlyContribution + _graceFee) {
                    revert LiquiPoolVault__InsufficientContribution(msg.value, _monthlyContribution + _graceFee);
                }
                s_contributedDuringGracePeriod[msg.sender] = true;
                (, , , , , , uint256 graceScoreFee, ) = i_poolHandler.getScoreConstants();

                i_poolHandler.decreaseScore(msg.sender, graceScoreFee);

                (bool sent, ) = payable(i_poolHandler.getPoolManager()).call{value: _graceFee}(""); 

            } else {
                // Both windows expired — contribution not accepted on-chain
                // Pool manager must call coverMemberDefault() instead
                revert LiquiPoolVault__ContributionWindowClosed();
            }

            s_hasContributedThisRound[msg.sender] = true;
            emit ContributionReceived(msg.sender, s_currentRound + 1, msg.value);
        }


    /***    MEMBER — BIDDING    */

    /**
     * @notice Member submits a bid to receive the pool payout at a discounted amount.
     *         Every new bid must be strictly lower than the current lowest bid.
     *         The member offering to accept the least receives the payout at round close.
     * @dev Only members who have not yet received a payout in any prior round may bid.
     *      Bidding earns a score bonus regardless of whether the member wins.
     * @param bidAmount The amount in wei the member is willing to accept as their payout.
     *                  Must be lower than s_currentLowestBid.
     */
    function submitBid(uint256 bidAmount)
        public
        onlyWhenPoolActive
        onlyWhenBiddingActive
    {
        if (!i_poolHandler.isMemberEnrolled(msg.sender)) {
            revert LiquiPoolVault__CallerIsNotEnrolledMember();
        }
        if (s_hasReceivedPayout[msg.sender]) {
            revert LiquiPoolVault__MemberAlreadyReceivedPayout();
        }
        if (bidAmount >= s_currentLowestBid) {
            revert LiquiPoolVault__BidNotLowerThanCurrentLowest();
        }

        s_currentLowestBid    = bidAmount;

        if(s_currentLowestBidder != msg.sender)
        s_currentLowestBidder = msg.sender;
       
        (, , , , uint256 scoreOnBidParticipation , , ,) = i_poolHandler.getScoreConstants();
        i_poolHandler.increaseScore(msg.sender, scoreOnBidParticipation);

        emit BidSubmitted(msg.sender, bidAmount, s_currentRound + 1);
    }


   /***   SETTLEMENT   */

    /**
     * @notice Settles the current round — verifies all contributions, selects a winner,
     *         and distributes funds according to the protocol split.
     * @notice If there is a member who has not contributed yet and also pool manager also has not contributed in favour of that defaulter then the amount is come to the pool from  security money deposited by pool manager
     *
     * @dev Settlement split when a bid exists:
     *        winnerPayout        = lowestBid × 95%           (sent to winning bidder)
     *        treasuryFromBid     = lowestBid × 5%            (sent to pool manager / treasury)
     *        discount            = totalPool − lowestBid
     *        memberDividend      = discount × 4/5            (distributed equally to all members)
     *        treasuryFromDiscount= discount × 1/5            (sent to pool manager / treasury)
     *
     *      Settlement split when no bid was placed (pseudo-random fallback):
     *        winnerPayout        = totalPool × 90%           (sent to random eligible member)
     *        memberDividend      = totalPool × 5%            (distributed equally to all members)
     *        treasury            = totalPool × 5%            (sent to pool manager / treasury)
     *
     *      TODO: Replace pseudo-random fallback with Chainlink VRF in future upgrade.
     */
    function settleCurrentRound()
        public
        onlyPoolManager
        onlyWhenPoolActive
        onlyWhenBiddingClosed
        onlyWhenRoundsRemaining
    {
        address[] memory allMembers = i_poolHandler.getEnrolledMembers();

        // ── Verify all members have contributed if no then deduct from security money deposit by pool manager ──
        for (uint256 i = 0; i < allMembers.length; i++) {
            if (!s_hasContributedThisRound[allMembers[i]]) {
                _coverMemberDefault(allMembers[i]);
            }
        }

        uint256 totalPool = i_poolHandler.getMonthlyContributionAmount() * allMembers.length;
        address roundWinner;
        uint256 winnerPayout;
        uint256 memberDividendTotal;
        uint256 treasuryAmount;

        if (s_currentLowestBidder != address(0)) {
            // ── Path A: valid bid exists ─────────
            uint256 lowestBid       = s_currentLowestBid;
            winnerPayout            = (lowestBid * 95) / 100;
            treasuryAmount          = lowestBid - winnerPayout;
            uint256 discount        = totalPool - lowestBid;
            memberDividendTotal     = (discount * 4) / 5;
            treasuryAmount         += discount - memberDividendTotal;
            roundWinner             = s_currentLowestBidder;
    
            (, , , , , uint256 scoreBidWinner, ,) = i_poolHandler.getScoreConstants();

            i_poolHandler.increaseScore(roundWinner, scoreBidWinner);
        } else {
            // ── Path B: no bid — pseudo-random fallback ──
            // TODO: Replace with Chainlink VRF request in future upgrade
            uint256 randomIndex = uint256(
                keccak256(abi.encodePacked(block.timestamp, block.prevrandao, s_currentRound))
            ) % s_eligibleBidders.length;

            roundWinner         = s_eligibleBidders[randomIndex];
            winnerPayout        = (totalPool * 90) / 100;
            memberDividendTotal = (totalPool * 5) / 100;
            treasuryAmount      = totalPool - winnerPayout - memberDividendTotal;
        }

        // ── Record winner ────────────────────────
        s_roundWinners.push(roundWinner);
        s_hasReceivedPayout[roundWinner] = true;

        // Remove winner from eligible bidders list
        for (uint256 i = 0; i < s_eligibleBidders.length; i++) {
            if (s_eligibleBidders[i] == roundWinner) {
                s_eligibleBidders[i] = s_eligibleBidders[s_eligibleBidders.length - 1];
                s_eligibleBidders.pop();
                break;
            }
        }

        // ── Distribute member dividends ──────────
        uint256 perMemberDividend = memberDividendTotal / allMembers.length;
        uint256 dust              = memberDividendTotal - (perMemberDividend * allMembers.length);

        for (uint256 i = 0; i < allMembers.length; i++) {
            if (perMemberDividend > 0) {
                (bool sent, ) = payable(allMembers[i]).call{value: perMemberDividend}("");
                if (!sent) revert LiquiPoolVault__TransferFailed(allMembers[i], perMemberDividend);
            }
        }

        // Dust from dividend rounding goes to treasury
        treasuryAmount += dust;

        // ── Send treasury amount to pool manager ─
        (bool treasurySent, ) = payable(i_poolHandler.getPoolManager()).call{value: treasuryAmount}("");
        if (!treasurySent) revert LiquiPoolVault__TransferFailed(i_poolHandler.getPoolManager(), treasuryAmount);

        // ── Pay round winner ─────────────────────
        (bool winnerSent, ) = payable(roundWinner).call{value: winnerPayout}("");
        if (!winnerSent) revert LiquiPoolVault__TransferFailed(roundWinner, winnerPayout);

        s_isCurrentRoundSettled = true;

        emit RoundSettled(roundWinner, winnerPayout, s_currentRound + 1);
    }


   /***   GETTER FUNCTIONS   */
  
 
    /// @notice Returns the current round number (1-indexed)
    function getCurrentRound() public view returns (uint256) {
        return s_currentRound + 1;
    }

    /// @notice Returns whether the bidding round is currently active
    function isBiddingRoundActive() public view returns (bool) {
        return s_isBiddingRoundActive;
    }

    /// @notice Returns the current lowest bid amount in wei
    function getCurrentLowestBid() public view returns (uint256) {
        return s_currentLowestBid;
    }

    /// @notice Returns the address of the current lowest bidder
    function getCurrentLowestBidder() public view returns (address) {
        return s_currentLowestBidder;
    }

    /// @notice Returns whether the current round has been settled
    function isCurrentRoundSettled() public view returns (bool) {
        return s_isCurrentRoundSettled;
    }

    /// @notice Returns all round winners in order
    function getRoundWinners() public view returns (address[] memory) {
        return s_roundWinners;
    }

    /// @notice Returns the winner of the most recently settled round
    function getMostRecentRoundWinner() public view returns (address) {
        if (s_roundWinners.length == 0) return address(0);
        return s_roundWinners[s_roundWinners.length - 1];
    }

    /// @notice Returns whether a member has already received a payout in this cycle
    function hasMemberReceivedPayout(address member) public view returns (bool) {
        return s_hasReceivedPayout[member];
    }

    /// @notice Returns whether a member has contributed in the current round
    function hasMemberContributedThisRound(address member) public view returns (bool) {
        return s_hasContributedThisRound[member];
    }

    /// @notice Returns all members who have not yet contributed this round
    function getMembersNotYetContributed() public view returns (address[] memory) {
        address[] memory allMembers = i_poolHandler.getEnrolledMembers();
        address[] memory pending    = new address[](allMembers.length);
        uint256 count               = 0;

        for (uint256 i = 0; i < allMembers.length; i++) {
            if (!s_hasContributedThisRound[allMembers[i]]) {
                pending[count] = allMembers[i];
                count++;
            }
        }

        assembly { mstore(pending, count) }
        return pending;
    }

    /// @notice Returns all members who have contributed this round
    function getMembersContributedThisRound() public view returns (address[] memory) {
        address[] memory allMembers   = i_poolHandler.getEnrolledMembers();
        address[] memory contributed  = new address[](allMembers.length);
        uint256 count                 = 0;

        for (uint256 i = 0; i < allMembers.length; i++) {
            if (s_hasContributedThisRound[allMembers[i]]) {
                contributed[count] = allMembers[i];
                count++;
            }
        }

        assembly { mstore(contributed, count) }
        return contributed;
    }

    /// @notice Returns all members still eligible to receive a payout (have not won yet)
    function getEligibleBidders() public view returns (address[] memory) {
        return s_eligibleBidders;
    }

  

    /// @notice Returns the vault's current ETH balance
    function getVaultBalance() public view returns (uint256) {
        return address(this).balance;
    }


    // ═══════════════════════════════════════════════
    //  FALLBACK
    // ═══════════════════════════════════════════════

    receive() external payable {}
}