// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or 
 * any kind of contract that will be deployed behind a proxy.
 */
abstract contract Initializable {

    bool public initialized;

    /**
     * @dev To initialize only once.
     */
    function _initialize() internal {
        require(!initialized, "Initializable: initialized already");
        initialized = true;
    }

    modifier onlyInitialized() {
        require(initialized, "Initializable: uninitialized");
        _;
    }

}
