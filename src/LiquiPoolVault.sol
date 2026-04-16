// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import { LiquiPoolHandler } from "./LiquiPool.sol";

contract LiquiPoolVault {
    /** ERRORS */
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

  

    /** EVENTS */
    event SecurityMoneyReleased();
    event MonthlyDepositSubmitted(address indexed player);
    event SecurityMoneyDeposited();
    event PoolIsReset();
    event MonthlyContributionStatusReset();
    event newBidPlaced(address indexed bidder, uint256 indexed _bidAmount);





/*** MODIFIERS  */

    modifier onlyPoolMaker() {
        if(msg.sender != poolHandler.s_poolManager())
        {
            revert LiquiPoolVault__OnlyPoolManager();
        }
        _;      
    }

    modifier isBidWindowOpen() {
         if(s_isBidWindowOpen == false)
         {
             revert LiquiPoolVault__BidWindowIsNotOpen();
         }

         _;
    }


    modifier isBidWindowClosed() {
         if(s_isBidWindowOpen == true)
         {
             revert LiquiPoolVault__BidWindowIsOpen();
         }

         _;
    }



        /** STATE VARIABLES */
    LiquiPoolHandler private poolHandler;
    bool private s_isSecurityDepositSubmitted;
    uint256 private s_securityDeposit;
    address[] public s_holderOfEachMonth;   // who won the bid every month

    mapping(address => bool) private s_hasContributedThisMonth;

    address public s_currentMinBidder;
    uint256 public s_currentMinBid;
    address[] public s_remainingPlayers;

    bool public s_isBidWindowOpen;

    constructor(address _poolHandler) {
        poolHandler = LiquiPoolHandler(_poolHandler);
        s_isSecurityDepositSubmitted = false;
        s_remainingPlayers = poolHandler.getAllowedPlayers();
        s_currentMinBid = poolHandler.getPerPersonContributionPerMonth() * poolHandler.getAllowedPlayers().length;
        s_currentMinBidder = address(0);
        s_isBidWindowOpen = false;
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

         if(s_securityDeposit <= 0)
         {
            revert LiquiPoolVault__NotEnoughSecurityDepositToRelease();
         }
     
            s_isSecurityDepositSubmitted = false;
            s_securityDeposit = 0;
            (bool success, ) = payable(poolHandler.getPoolManager()).call{value: s_securityDeposit}("");

            if(!success) {
                revert LiquiPoolVault__TransferFailed();
            }

            emit SecurityMoneyReleased();
    }

    function resetPool() public onlyPoolMaker {
        if(poolHandler.getPoolState() != LiquiPoolHandler.LiquiPoolState.CLOSED)
         {
           revert LiquiPoolVault__IsNotClosed();
         }

         for(uint256 i = 0; i < s_holderOfEachMonth.length; i++)
         {
            s_hasContributedThisMonth[s_holderOfEachMonth[i]] = false;
         }

         delete s_holderOfEachMonth;
         s_securityDeposit = 0;
         s_isSecurityDepositSubmitted = false;
        //  delete poolHandler.s_allowedPlayers();

         emit PoolIsReset();
    }

    function resetMonthlyContributionStatus() public onlyPoolMaker {
        if(poolHandler.getPoolState() != LiquiPoolHandler.LiquiPoolState.OPEN)
         {
           revert LiquiPoolVault__IsNotOpen();
         }

         address[] memory allPlayers = poolHandler.getAllowedPlayers();

         for(uint256 i = 0; i < allPlayers.length; i++)
         {
            s_hasContributedThisMonth[allPlayers[i]] = false;
         }

         emit MonthlyContributionStatusReset();
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

      function makeBidForThisMonth(uint256 _bidAmount) public isBidWindowOpen {
           if(_bidAmount <= s_currentMinBid)
           {
            revert LiquiPoolVault__NotEnoughBidAmount();
           }

           if(poolHandler.getWhetherPlayerIsAllowedOrNot(msg.sender))
           {
              revert LiquiPoolVault__PlayerIsNotAllowed();
           }

           for(uint256 i = 0; i < s_holderOfEachMonth.length; i++)
           {
            if(s_holderOfEachMonth[i] == msg.sender)
            {
                revert LiquiPoolVault__AlreadyWonBid();
            }
           }

             if(s_currentMinBidder != msg.sender)
             {
                s_currentMinBidder = msg.sender;
             }

             s_currentMinBid = _bidAmount;

          emit newBidPlaced(msg.sender, _bidAmount);
      }

      function openBidWindow() public  {
          s_isBidWindowOpen = true;
      }

      function closeBidWindow() public {
          s_isBidWindowOpen = false;
      }

    function distributeMonthlyDeposit() public payable isBidWindowClosed {
          uint256 totalPoolThisMonth = poolHandler.getPerPersonContributionPerMonth() * poolHandler.getAllowedPlayers().length;



            if(s_currentMinBidder == address(0))
            {
                s_currentMinBid = totalPoolThisMonth;
                uint256 randomNumber = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao))) % poolHandler.getAllowedPlayers().length;
                s_currentMinBidder = s_remainingPlayers[randomNumber];
            }
    
            uint256 amountTranferToBidder = (s_currentMinBid * 95) / 100;

            uint256 remAmount = totalPoolThisMonth - s_currentMinBid;

            uint256 amountToBeDistributed = (remAmount * 95) / 100;
            uint256 amountToInvest = totalPoolThisMonth - amountToBeDistributed - amountTranferToBidder;

            uint256 perPersonGet = amountToBeDistributed / poolHandler.getAllowedPlayers().length;

            s_holderOfEachMonth.push(s_currentMinBidder);

            for(uint256 i=0; i<s_remainingPlayers.length; i++)
            {
                if(s_remainingPlayers[i] == s_currentMinBidder)
                {
                    s_remainingPlayers[i] = s_remainingPlayers[s_remainingPlayers.length - 1];
                    s_remainingPlayers.pop();
                    break;
                }
            }

            bool success = false;

              /** Distribute  */
            for(uint256 i = 0; i < poolHandler.getAllowedPlayers().length; i++)
             {
                ( success, ) = payable(poolHandler.getAllowedPlayers()[i]).call{value: perPersonGet}("");
    
                if(!success) {
                    revert LiquiPoolVault__TransferFailed();
                }
             }

        ( success, ) = payable(poolHandler.getPoolManager()).call{value: amountToInvest}("");

            if(!success) {
              revert LiquiPoolVault__TransferFailed();
         }

         ( success, ) = payable(s_currentMinBidder).call{value: amountTranferToBidder}("");

            if(!success) {
                    revert LiquiPoolVault__TransferFailed();
         }

   
        s_currentMinBidder = address(0);
        s_currentMinBid = totalPoolThisMonth;
      }






}