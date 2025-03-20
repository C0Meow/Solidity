 // SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


 // hw8_VulnerableEscrow.sol - Find and fix the vulnerabilities
contract hw8_VulnerableEscrow {
    address public buyer;
    address public seller;
    uint public amount;
    bool public isDeposited;
    
    // Vulnerability 1: No access control
    function deposit() public payable {
        isDeposited = true;
    }
    
    // Vulnerability 2: No balance check
    function withdraw() public {
        payable(msg.sender).transfer(amount);
    }
    
    // Vulnerability 3: No state management
    function release() public {
        payable(seller).transfer(amount);
    }
}
