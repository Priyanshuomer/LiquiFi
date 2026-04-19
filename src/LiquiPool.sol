// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title LiquiPoolHandler
 * @notice Manages member enrollment, pool lifecycle state, and pool manager access for the LiquiPool decentralized protocol.
 * @dev This contract acts as the identity and access layer. All financial logic lives in LiquiPoolVault.sol. Deploy this first, then pass its address into the Vault constructor.
 */
contract LiquiPoolHandler {
    /** ERRORS */

    /// @notice Thrown when a non-owner calls an owner-restricted function
    error LiquiPool__OnlyOwner();

    /// @notice Thrown when vault address is already set and cannot be changed
    error LiquiPool__VaultAlreadySet();

    /// @notice Thrown when a non-pool-manager calls a manager-restricted function
    error LiquiPool__OnlyPoolManager();


    /// @notice Thrown when a member tries to request enrollment but is already approved
    error LiquiPool__MemberAlreadyEnrolled();

    /// @notice Thrown when trying to remove a member who is not currently enrolled
    error LiquiPool__MemberNotEnrolled();
  
   /// @notice Thrown when a member tries to request to enroll but is already requested before for enrollment
    error LiquiPool__MemberAlreadyRequested();

   // @notice Thrown when a member tries to request to enroll but pool is not in enrollment phase
    error LiquiPool__NotInEnrollmentPhase();

    error LiquiPool__OnlyVaultContract();



    /** EVENTS */

    /// @notice Emitted when a member submits an enrollment request
    event EnrollmentRequested(address indexed applicant);

    event VaultContractSet(address _vaultAddress);

    /// @notice Emitted when the pool manager approves a member's enrollment
    event MemberEnrolled(address indexed member);

    /// @notice Emitted when a member is removed from the pool
    event MemberRemoved(address indexed member);

    /// @notice Emitted when the pool manager role is transferred
    event PoolManagerTransferred(address indexed previousManager, address indexed newManager);

    /// @notice Emitted when the pool state changes
    event PoolStateChanged(PoolState indexed previousState, PoolState indexed newState);

    /// @notice Emitted when the Owner role is transferred
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    event MemberScoreUpdated(address indexed member, uint256 indexed prevScore, uint256 indexed newScore);



   /** TYPES */

    /**
     * @notice Represents the current operational phase of the pool.
     * @dev ENROLLMENT  — pool is open, members can request to join.
     *      ACTIVE      — pool is running, contributions and bidding are live.
     *      SUSPENDED   — pool is temporarily halted by the manager.
     *      CONCLUDED   — all rounds complete, pool is permanently closed.
     */
    enum PoolState {
        ENROLLMENT,
        ACTIVE,
        SUSPENDED,
        CONCLUDED
    }

    /** STATE VARIABLES */

    /// @notice Current operational phase of the pool
    PoolState private s_poolState;

    /// @notice Maps member address to whether they are approved and active
    mapping(address => bool) private s_isMemberEnrolled;


   /// @notice Maps member address to whether they requested to enter 
    mapping(address => bool) private s_isMemberRequested;


    /// @notice Deployer of this contract — has highest privilege level
    address public s_owner;

    /// @notice Pool manager (foreman) — manages day-to-day pool operations
    address public s_poolManager;

    /// @notice Ordered list of all currently enrolled members
    address[] private s_enrolledMembers;

    // @notice Ordered list of all requested members
    address[] private s_requestedMembers;

    address private  s_vaultContract;


    // ── Reputation scores ────────────────────────
    /// @notice Maps member address to their internal reputation score (0–100)
    mapping(address => uint256) private s_memberScore;

    /// @notice Whether a member's score has been initialized
    mapping(address => bool) private s_isMemberScoreInitialized;

    
    
    /****
    //  SCORE CONSTANTS
    //  Internal scale: 0–100. Displayed as 1–5 stars.
    //  1★ = 0–20  | 2★ = 21–40 | 3★ = 41–60
    //  4★ = 61–80 | 5★ = 81–100
    */ 
    
    /// @dev Starting score for every newly enrolled member (maps to 2 stars)
    uint256 private constant SCORE_INITIAL                    = 40;

    /// @dev Maximum achievable score
    uint256 private constant SCORE_MAXIMUM                    = 100;

    /// @dev Minimum score floor — score never drops below this
    uint256 private constant SCORE_MINIMUM                    = 0;

    /// @dev Awarded when member contributes within the primary contribution window
    uint256 private constant SCORE_BONUS_ON_TIME_CONTRIBUTION = 10;

    /// @dev Awarded when member places a bid during an active bidding round
    uint256 private constant SCORE_BONUS_BID_PARTICIPATION    = 5;

    /// @dev Awarded when member wins a round via the bidding process
    uint256 private constant SCORE_BONUS_BID_WINNER           = 8;

    /// @dev Deducted when member contributes during the grace period (late, with penalty)
    uint256 private constant SCORE_PENALTY_GRACE_PERIOD       = 10;

    /// @dev Deducted when pool manager must cover a member's defaulted contribution
    uint256 private constant SCORE_PENALTY_DEFAULT_COVERED    = 35;

    
    // ── Financial parameters ─────────────────────
    /// @notice Fixed monthly contribution amount each member must pay (in wei)
    uint256 private s_monthlyContributionAmount;

    /// @notice Security deposit amount the pool manager must lock before pool activates (in wei)
    uint256 private s_requiredSecurityDeposit;

    /// @notice Grace period late contribution penalty fee sent to pool manager (in wei)
    uint256 private s_gracePeriodPenaltyFee;

    // ── Security deposit tracking ────────────────
    /// @notice Whether the pool manager has locked the security deposit
    bool private s_isSecurityDepositLocked;

    /// @notice Current balance of the security deposit held in this contract
    uint256 private s_securityDepositBalance;

    // ── Contribution timing ──────────────────────

    /// @notice Duration of the primary contribution window in seconds (default 3 days)
    uint256 private s_primaryWindowDuration;

    /// @notice Duration of the grace period window after primary window closes (default 2 days)
    uint256 private s_gracePeriodDuration;


    /** CONSTRUCTOR */
    /**
     * @param _poolManager                Address of the pool manager (foreman)
     * @param _monthlyContributionAmount   Fixed monthly contribution per member in wei
     * @param _requiredSecurityDeposit     Security deposit the pool manager must lock in wei
     * @param _gracePeriodPenaltyFee       Late contribution penalty forwarded to pool manager in wei
     * @param _primaryWindowDuration       Duration of on-time contribution window in seconds
     * @param _gracePeriodDuration         Duration of grace period after primary window in seconds
     */
    constructor(address _poolManager, uint256 _monthlyContributionAmount, uint256 _requiredSecurityDeposit, uint256 _gracePeriodPenaltyFee, uint256 _primaryWindowDuration, uint256 _gracePeriodDuration) {
        s_owner = msg.sender;
        s_poolManager = _poolManager;
        s_poolState = PoolState.ENROLLMENT;

        s_monthlyContributionAmount  = _monthlyContributionAmount;
        s_requiredSecurityDeposit    = _requiredSecurityDeposit;
        s_gracePeriodPenaltyFee      = _gracePeriodPenaltyFee;
        s_primaryWindowDuration      = _primaryWindowDuration;
        s_gracePeriodDuration        = _gracePeriodDuration;
        s_isSecurityDepositLocked    = false;
    }

   /** MODIFIERS */

    /// @dev Restricts function to the contract owner only
    modifier onlyOwner() {
        if (msg.sender != s_owner) revert LiquiPool__OnlyOwner();
        _;
    }

    /// @dev Restricts function to the pool manager only
    modifier onlyPoolManager() {
        if (msg.sender != s_poolManager) revert LiquiPool__OnlyPoolManager();
        _;
    }

   /// @dev Restricts function to be called when pool is in ENROLLMENT PHASE
    modifier onlyDuringEnrollment() {
        if(s_poolState != PoolState.ENROLLMENT)
          revert LiquiPool__NotInEnrollmentPhase();

          _;
    }

    modifier onlyVaultContract() {
        if(msg.sender != s_vaultContract)
         revert LiquiPool__OnlyVaultContract();

         _;
    }

 

   /** ENROLLMENT FUNCTIONS */

    /**
     * @notice Allows any address to submit a request to join the pool.
     *         Pool manager must then call approveMemberEnrollment() to confirm.
     * @dev Only callable during ENROLLMENT phase.
     *      Does not add member to the active list — that happens on approval.
     */
    function requestEnrollment() public onlyDuringEnrollment {
        if (s_isMemberEnrolled[msg.sender]) {
            revert LiquiPool__MemberAlreadyEnrolled();
        }

        if(s_isMemberRequested[msg.sender])
          revert LiquiPool__MemberAlreadyRequested();

        s_isMemberRequested[msg.sender] = true;
        s_requestedMembers.push(msg.sender);


        emit EnrollmentRequested(msg.sender);
    }

    /**
     * @notice Pool manager approves a pending enrollment request.
     *         Adds the applicant to the enrolled members list.
     * @dev Only callable by pool manager.
     * @param applicant Address of the member to approve
     */
    function approveMemberEnrollment(address applicant) public onlyPoolManager {
        if (s_isMemberEnrolled[applicant]) {
            revert LiquiPool__MemberAlreadyEnrolled();
        }
        s_isMemberEnrolled[applicant] = true;
        s_enrolledMembers.push(applicant);

        emit MemberEnrolled(applicant);
    }

    /**
     * @notice Removes an enrolled member from the pool.
     *         Uses swap-and-pop for gas-efficient array removal.
     * @dev Only callable by pool manager.
     * @param member Address of the member to remove
     */
    function removeMember(address member) public onlyPoolManager {
        if (!s_isMemberEnrolled[member]) {
            revert LiquiPool__MemberNotEnrolled();
        }

        s_isMemberEnrolled[member] = false;

        for (uint256 i = 0; i < s_enrolledMembers.length; i++) {
            if (s_enrolledMembers[i] == member) {
                s_enrolledMembers[i] = s_enrolledMembers[s_enrolledMembers.length - 1];
                s_enrolledMembers.pop();
                break;
            }
        }

        emit MemberRemoved(member);
    }



    /** POOL STATE MANAGEMENT */

    /**
     * @notice Transitions the pool from one phase to another phase. 
     * @dev Only callable by pool manager during ENROLLMENT phase.
     */
    function changePoolState(PoolState _newState) public onlyPoolManager {
        PoolState previous = s_poolState;
        s_poolState = _newState;

        emit PoolStateChanged(previous, s_poolState);
    }


    /** VAULT-ONLY FUNCTIONS ,  Only callable by the LiquiPoolVault contract */

    /**
    * @notice Records that the security deposit has been locked by the pool manager.
    * @dev Called by LiquiPoolVault when pool manager calls lockSecurityDeposit().
    * @param amount Amount locked in wei
    */
    function recordSecurityDepositLocked(uint256 amount) external onlyVaultContract {
        s_isSecurityDepositLocked    = true;
        s_securityDepositBalance    += amount;
    }

    /**
    * @notice Records that the security deposit has been released back to pool manager.
    * @dev Called by LiquiPoolVault when pool manager calls releaseSecurityDeposit().
    */
    function recordSecurityDepositReleased() external onlyVaultContract {
        s_isSecurityDepositLocked   = false;
        s_securityDepositBalance    = 0;
    }

    /**
    * @notice Deducts from security deposit balance when pool manager covers a member default.
    * @dev Called by LiquiPoolVault when coverMemberDefault() is executed.
    * @param amount Amount deducted in wei
    */
    function deductFromSecurityDeposit(uint256 amount) external onlyVaultContract {
        s_securityDepositBalance -= amount;
    }


     /***   SCORE HELPERS    */
    /**
     * @dev Initializes a member's score to SCORE_INITIAL if not already set.
     *      Called lazily on first score interaction.
     * @param member Address of the member
     */
    function initializeMemberScore(address member) public onlyVaultContract {
        if (!s_isMemberScoreInitialized[member]) {
            s_memberScore[member] = SCORE_INITIAL;
            s_isMemberScoreInitialized[member] = true;
        }
    }

    /**
     * @dev Increases a member's score by the given amount, capped at SCORE_MAXIMUM.
     * @param member Address of the member
     * @param points Number of points to add
     */
    function increaseScore(address member, uint256 points) external onlyVaultContract {
        initializeMemberScore(member);
        uint256 previous = s_memberScore[member];
        uint256 updated  = previous + points;
        if (updated > SCORE_MAXIMUM) updated = SCORE_MAXIMUM;
        s_memberScore[member] = updated;
        emit MemberScoreUpdated(member, previous, updated);
    }

    /**
     * @dev Decreases a member's score by the given amount, floored at SCORE_MINIMUM.
     * @param member Address of the member
     * @param points Number of points to deduct
     */
    function decreaseScore(address member, uint256 points) external {
        initializeMemberScore(member);
        uint256 previous = s_memberScore[member];
        uint256 updated  = previous > points ? previous - points : SCORE_MINIMUM;
        s_memberScore[member] = updated;
        emit MemberScoreUpdated(member, previous, updated);
    }




 


   /** OWNER FUNCTIONS */

    /**
     * @notice Transfers the pool manager role to a new address.
     * @dev Only callable by contract owner.
     * @param newManager Address of the incoming pool manager
     */
    function transferPoolManager(address newManager) public onlyOwner {
        address previous = s_poolManager;
        s_poolManager = newManager;
        emit PoolManagerTransferred(previous, newManager);
    }


    /**
     * @notice Transfers the Ownership to a new address.
     * @dev Only callable by contract owner.
     * @param newOwner Address of the new Owner 
     */
    function transferOwnership(address newOwner) public onlyOwner {
        address previous = s_owner;
        s_owner = newOwner;

        emit PoolManagerTransferred(previous, s_owner);
    }


    /**
    * @notice Registers the LiquiPoolVault contract address after deployment.
    *         Can only be set once — once set it is permanently locked.
    * @dev Called by deploy script immediately after Vault is deployed.
    *      Prevents any future tampering with the vault reference.
    * @param _vaultContractAddress Address of the deployed LiquiPoolVault
    */
    function updateVaultContractAddress(address _vaultContractAddress) external onlyOwner {
        if (s_vaultContract != address(0)) {
            revert LiquiPool__VaultAlreadySet();
        }

        s_vaultContract = _vaultContractAddress;
        emit VaultContractSet(_vaultContractAddress);
    }



   /** GETTER FUNCTIONS */

    /// @notice Returns the current pool manager address
    function getPoolManager() public view returns (address) {
        return s_poolManager;
    }



    /// @notice Returns the current operational state of the pool
    function getPoolState() public view returns (PoolState) {
        return s_poolState;
    }

    /// @notice Returns whether a given address is an enrolled and active member
    function isMemberEnrolled(address member) public view returns (bool) {
        return s_isMemberEnrolled[member];
    }

    /// @notice Returns the full list of currently enrolled members
    function getEnrolledMembers() public view returns (address[] memory) {
        return s_enrolledMembers;
    }

    /// @notice Returns whether a given address is requested to enroll 
    function isMemberRequestedToEnroll(address member) public view returns (bool) {
        return s_isMemberRequested[member];
    }

    /// @notice Returns the full list of currently requested members
    function getRequestedMembers() public view returns (address[] memory) {
        return s_requestedMembers;
    }


    /// @notice Returns the total number of enrolled members
    function getEnrolledMemberCount() public view returns (uint256) {
        return s_enrolledMembers.length;
    }


     /// @notice Returns the total number of requested members
    function getRequestedMemberCount() public view returns (uint256) {
        return s_requestedMembers.length;
    }




    /// @notice Returns the raw internal reputation score (0–100) for a given member
    function getMemberScore(address member) public view returns (uint256) {
        if (!s_isMemberScoreInitialized[member]) return SCORE_INITIAL;
        return s_memberScore[member];
    }

    /// @notice Returns the star rating (1–5) derived from the member's internal score
    /// @dev 1★ = 0–20 | 2★ = 21–40 | 3★ = 41–60 | 4★ = 61–80 | 5★ = 81–100
    function getMemberStarRating(address member) public view returns (uint256) {
        uint256 score = getMemberScore(member);
        if (score <= 20) return 1;
        if (score <= 40) return 2;
        if (score <= 60) return 3;
        if (score <= 80) return 4;
        return 5;
    }

    /// @notice Returns whether a member's score has been initialized yet
    function isMemberScoreInitialized(address member) public view returns (bool) {
        return s_isMemberScoreInitialized[member];
    }

    /// @notice Returns all score constants used by the protocol
    /// @return initial        Starting score for new members
    /// @return maximum        Score ceiling
    /// @return minimum        Score floor
    /// @return bonusOnTime    Points awarded for on-time contribution
    /// @return bonusBid       Points awarded for placing a bid
    /// @return bonusWinner    Points awarded for winning a round
    /// @return penaltyGrace   Points deducted for grace period contribution
    /// @return penaltyDefault Points deducted when pool manager covers a default
    function getScoreConstants() public pure returns (
        uint256 initial,
        uint256 maximum,
        uint256 minimum,
        uint256 bonusOnTime,
        uint256 bonusBid,
        uint256 bonusWinner,
        uint256 penaltyGrace,
        uint256 penaltyDefault
    ) {
        return (
            SCORE_INITIAL,
            SCORE_MAXIMUM,
            SCORE_MINIMUM,
            SCORE_BONUS_ON_TIME_CONTRIBUTION,
            SCORE_BONUS_BID_PARTICIPATION,
            SCORE_BONUS_BID_WINNER,
            SCORE_PENALTY_GRACE_PERIOD,
            SCORE_PENALTY_DEFAULT_COVERED
        );
    }

 

    /// @notice Returns the fixed monthly contribution amount in wei
    function getMonthlyContributionAmount() public view returns (uint256) {
        return s_monthlyContributionAmount;
    }

    /// @notice Returns the required security deposit amount in wei
    function getRequiredSecurityDeposit() public view returns (uint256) {
        return s_requiredSecurityDeposit;
    }

    /// @notice Returns the grace period penalty fee in wei
    function getGracePeriodPenaltyFee() public view returns (uint256) {
        return s_gracePeriodPenaltyFee;
    }

    /// @notice Returns whether the pool manager has locked the security deposit
    function isSecurityDepositLocked() public view returns (bool) {
        return s_isSecurityDepositLocked;
    }

    /// @notice Returns the current security deposit balance held in the contract
    function getSecurityDepositBalance() public view returns (uint256) {
        return s_securityDepositBalance;
    }

  

    /// @notice Returns the duration of the primary contribution window in seconds
    function getPrimaryWindowDuration() public view returns (uint256) {
        return s_primaryWindowDuration;
    }

    /// @notice Returns the duration of the grace period window in seconds
    function getGracePeriodDuration() public view returns (uint256) {
        return s_gracePeriodDuration;
    }

}
