// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract LuckyDraw {
    // Contract owner address who can draw winners and withdraw remaining funds
    address payable public owner;
    // Price of each lottery ticket in wei
    uint public ticketPrice; 
    // Total number of tickets purchased
    uint public totalTickets;
    // Total value of all ticket purchases
    uint public prizePool;
    // Maps user addresses to number of tickets they own
    mapping(address => uint) public ticketsBought;
    // Array to keep track of all participants who have purchased tickets
    address[] public participants;

    // Event emitted when winners are drawn with their addresses
    event WinnersDrawn(address[] winners);

    // Initialize contract with ticket price
    constructor(uint _ticketPrice) {
        owner = payable(msg.sender);
        ticketPrice = _ticketPrice;
    }

    // Allow users to purchase tickets by sending ether
    function buyTicket() public payable {
        require(msg.value >= ticketPrice, "Insufficient funds for ticket");
        
        // If first time buyer, add to participants array
        if (ticketsBought[msg.sender] == 0) {
            participants.push(msg.sender);
        }
        
        // Update ticket counts and prize pool
        ticketsBought[msg.sender]++;
        totalTickets++;
        prizePool += msg.value;
    }

    // Draw specified number of winners and distribute prizes
    function drawWinners(uint numberOfWinners) public onlyOwner {
        require(numberOfWinners > 0, "Must draw at least one winner");
        require(numberOfWinners <= participants.length, "Not enough participants");
        require(totalTickets >= numberOfWinners, "Not enough tickets sold");

        // Create array to store winner addresses
        address[] memory winners = new address[](numberOfWinners);
        
        // Calculate prize distribution (90% of pool split among winners)
        uint totalPrize = (prizePool * 90) / 100;
        uint sharePerWinner = totalPrize / numberOfWinners;

        // Select winners and distribute prizes
        for (uint i = 0; i < numberOfWinners; i++) {
            winners[i] = selectRandomWinner();
            (bool sent, ) = payable(winners[i]).call{value: sharePerWinner}("");
            require(sent, "Failed to send Ether");
        }

        // Update prize pool and emit winners event
        prizePool -= totalPrize;
        emit WinnersDrawn(winners);
    }

    // Internal function to randomly select a winner based on ticket ownership
    function selectRandomWinner() private returns (address) {
        // Generate pseudo-random number using block data
        uint random = uint(keccak256(abi.encodePacked(
            blockhash(block.number - 1),
            block.timestamp,
            totalTickets
        )));
        
        // Get index within total ticket range
        uint winnerIndex = random % totalTickets;
        uint counter = 0;

        // Iterate through participants to find winning ticket
        for (uint i = 0; i < participants.length; i++) {
            address participant = participants[i];
            uint participantTickets = ticketsBought[participant];
            
            // Check if winning index falls within this participant's ticket range
            if (winnerIndex >= counter && winnerIndex < counter + participantTickets) {
                // Remove used ticket
                ticketsBought[participant]--;
                
                // If participant has no more tickets, remove from participants array
                if (ticketsBought[participant] == 0) {
                    participants[i] = participants[participants.length - 1];
                    participants.pop();
                }
                return participant;
            }
            counter += participantTickets;
        }
        revert("No winner found");
    }

    // Allow owner to withdraw remaining funds (10% of prize pool)
    function withdrawRemaining() public onlyOwner {
        (bool sent, ) = owner.call{value: address(this).balance}("");
        require(sent, "Failed to send Ether");
    }

    // View functions to get contract state
    function getTicketPrice() public view returns (uint) {
        return ticketPrice;
    }

    function getTotalTickets() public view returns (uint) {
        return totalTickets;
    }

    function getPrizePool() public view returns (uint) {
        return prizePool;
    }

    function getMyTickets() public view returns (uint) {
        return ticketsBought[msg.sender];
    }

    function getParticipants() public view returns (address[] memory) {
        return participants;
    }

    // Modifier to restrict function access to contract owner
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
}