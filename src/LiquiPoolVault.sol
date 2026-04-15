// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import { LiquiPoolHandler } from "./LiquiPool.sol";

contract LiquiPoolVault {
    LiquiPoolHandler private poolHandler;

    constructor(address _poolHandler) {
        poolHandler = LiquiPoolHandler(_poolHandler);
    }


}