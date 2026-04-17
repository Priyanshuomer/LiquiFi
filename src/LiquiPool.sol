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

    /// @notice Thrown when a non-pool-manager calls a manager-restricted function
    error LiquiPool__OnlyPoolManager();


    /// @notice Thrown when a member tries to request enrollment but is already approved
    error LiquiPool__MemberAlreadyEnrolled();

    /// @notice Thrown when trying to remove a member who is not currently enrolled
    error LiquiPool__MemberNotEnrolled();
  
   /// @notice Thrown when a member tries to request to enroll but is already requested before for enrollment
    error LiquiPool__MemberAlreadyRequested();



    /** EVENTS */

    /// @notice Emitted when a member submits an enrollment request
    event EnrollmentRequested(address indexed applicant);

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

 
    /// @notice Security deposit the pool manager must lock before pool starts (in wei)
    uint256 private s_requiredSecurityDeposit;

     /** CONSTRUCTOR */
    /**
     * @param _poolManager                Address of the pool manager (foreman)
     */
    constructor(address _poolManager) {
        s_owner = msg.sender;
        s_poolManager = _poolManager;
        s_poolState = PoolState.ENROLLMENT;
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
    function changePoolState(PoolState memory _newState) public onlyPoolManager {
        PoolState previous = s_poolState;
        s_poolState = _newState;

        emit PoolStateChanged(previous, s_poolState);
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

   /** GETTER FUNCTIONS */

    /// @notice Returns the current pool manager address
    function getPoolManager() public view returns (address) {
        return s_poolManager;
    }



    /// @notice Returns the current operational state of the pool
    function getPoolState() public view returns (PoolState memory) {
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
}
