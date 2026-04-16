// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import { LiquiPoolHandler } from "./LiquiPool.sol";

contract LiquiPoolVault {
    /** ERRORS */
    error LiquiPoolVault__NotEnoughSecurityDeposit(); 
    error LiquiPoolVault__IsNotClosed();
    error LiquiPoolVault__OnlyPoolManager();
    error LiquiPoolVault__TransferFailed();
    error LiquiPoolVault__NotEnoughMonthlyDeposit();
    error LiquiPoolVault__AlreadyContributedThisMonth();
    error LiquiPoolVault__PlayerIsNotAllowed();
  

    /** EVENTS */
    event SecurityMoneyReleased();
    event MonthlyDepositSubmitted(address indexed player);
    event SecurityMoneyDeposited();




/*** MODIFIERS  */

    modifier onlyPoolMaker() {
        if(msg.sender != poolHandler.s_poolManager())
        {
            revert LiquiPoolVault__OnlyPoolManager();
        }
        _;      
    }


        /** STATE VARIABLES */
    LiquiPoolHandler private poolHandler;
    bool private s_isSecurityDepositSubmitted;
    uint256 private s_securityDeposit;

    mapping(address => bool) private s_hasContributedThisMonth;

    constructor(address _poolHandler) {
        poolHandler = LiquiPoolHandler(_poolHandler);
        s_isSecurityDepositSubmitted = false;
    }
     
     /** Pool Manager Functions */
    function submitSecurityDeposit() public payable onlyPoolMaker {
         if(msg.value < poolHandler.getPoolMakerSecurityDeposit())
         {
           revert LiquiPoolVault__NotEnoughSecurityDeposit();
         }

         s_isSecurityDepositSubmitted = true;
         s_securityDeposit = msg.value;
         emit SecurityMoneyDeposited();
    }

    function releaseSecurityDeposit() public payable onlyPoolMaker {
         if(poolHandler.getPoolState() != LiquiPoolHandler.LiquiPoolState.CLOSED)
         {
           revert LiquiPoolVault__IsNotClosed();
         }
     
            s_isSecurityDepositSubmitted = false;
            s_securityDeposit = 0;
            (bool success, ) = payable(poolHandler.getPoolManager()).call{value: s_securityDeposit}("");

            if(!success) {
                revert LiquiPoolVault__TransferFailed();
            }

            emit SecurityMoneyReleased();
    }



    function submitMonthlyDepositOnBehalfOfOther(address player) public payable onlyPoolMaker
    {
          if(msg.value < poolHandler.getPerPersonContributionPerMonth())
            {
            revert LiquiPoolVault__NotEnoughMonthlyDeposit();
            }

            if(poolHandler.getWhetherPlayerIsAllowedOrNot(player) == false)
            {
                revert LiquiPoolVault__PlayerIsNotAllowed();
            }

            if(s_hasContributedThisMonth[player] == true)
            {
                revert LiquiPoolVault__AlreadyContributedThisMonth();
            }

            s_hasContributedThisMonth[player] = true;

            emit MonthlyDepositSubmitted(player);

    }

    
     /** Player's functions  */
      function contributeMonthly() public payable {
            if(msg.value < poolHandler.getPerPersonContributionPerMonth())
            {
            revert LiquiPoolVault__NotEnoughMonthlyDeposit();
            }

            if(poolHandler.getWhetherPlayerIsAllowedOrNot(msg.sender) == false)
            {
                revert LiquiPoolVault__PlayerIsNotAllowed();
            }

            if(s_hasContributedThisMonth[msg.sender] == true)
            {
                revert LiquiPoolVault__AlreadyContributedThisMonth();
            }

            s_hasContributedThisMonth[msg.sender] = true;
            emit MonthlyDepositSubmitted(msg.sender);
      }

}