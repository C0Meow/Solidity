// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract LuckyDraw {

    struct PastWinners {
        address userAddress;
        uint256 wins;
    }
    // Contract owner address who can draw winners and withdraw remaining funds
    address payable public owner;
    // Price of each lottery ticket in wei
    uint public ticketPrice; 
    // Total number of tickets purchased
    uint public totalTickets;
    // Total value of all ticket purchases
    uint public prizePool;
    // Maximum Tickets within a pool
    uint public consumedTickets;
    uint public availableTickets;
    // Maps user addresses to number of tickets they own
    mapping(address => uint) public ticketsBought;
    // Array to keep track of all participants who have purchased tickets
    address[] public participants;
    // hw: Maps user addresses to number of winnings they have
    PastWinners[] public pastWinners;
    address[] public winnerHistory;
    uint public last_X_Winners;


    // Event emitted when winners are drawn with their addresses
    event WinnersDrawn(address[] winners);
    event TicketPriceChanged(uint before, uint newPrice);
    event LogFallBack(address sender, uint value, bytes data);
    event TicketPurchashed(address addr, uint amt);
    event ParticipantArray(address[] part);
    event WinnersGuy(address winners);
    event loglog(uint a, uint b, uint c, uint d);
    event NewWinnerAdded(address winner, uint wins);


    // Initialize contract with ticket price
    constructor(uint _ticketPrice, uint _totalTickets, uint _xWinners) {
        owner = payable(msg.sender);
        ticketPrice = _ticketPrice;
        totalTickets = _totalTickets;
        availableTickets = _totalTickets;
        last_X_Winners = _xWinners;
    }

    fallback() external payable {
        emit LogFallBack(msg.sender,msg.value, msg.data);
    }

    receive() external payable {
        emit LogFallBack(msg.sender,msg.value, "");
    }

    //homework: numbers of ticket of a single buy
    // Allow users to purchase tickets by sending ether
    function buyTicket(uint numberOfTicket) public payable {
        //emit loglog(msg.value, ticketPrice, amtOfTicket, ticketPrice*amtOfTicket);
        require(msg.value >= ticketPrice*numberOfTicket, "Insufficient funds for ticket");
        require(numberOfTicket <= availableTickets, "Insufficient tickets for sale"); //Prevent having more than max tickets
        
        // If first time buyer, add to participants array
        if (ticketsBought[msg.sender] == 0) {
            participants.push(msg.sender);
        }
        
        // Update ticket counts and prize pool
        ticketsBought[msg.sender]+= numberOfTicket;
        consumedTickets += numberOfTicket;
        availableTickets = availableTickets - numberOfTicket;
        // availableTickets -= amtOfTicket;
        prizePool += msg.value;
        emit TicketPurchashed(msg.sender, numberOfTicket);
        emit ParticipantArray(participants);
    }

    function setTicketPrice(uint newPrice) public onlyOwner{
        require(newPrice > 0, "Invalid Number, price cant be less or equal than 0");
        ticketPrice = newPrice;
        emit TicketPriceChanged(ticketPrice, newPrice);
    }

    // Draw specified number of winners and distribute prizes
    function drawWinners(uint numberOfWinners) public onlyOwner {
        require(numberOfWinners > 0, "Must draw at least one winner"); //Ensure minimum 1 winner
        require(numberOfWinners <= participants.length, "Not enough participants, numbers of winners cant be larger than numbers of participants"); //Validate numberOfWinners against pool size
        require(consumedTickets >= numberOfWinners, "Too many winners");

        // Create array to store winner addresses
        address[] memory winners = new address[](numberOfWinners);
        
        // Calculate prize distribution (90% of pool split among winners)
        uint totalPrize = (prizePool * 90) / 100;
        uint sharePerWinner = totalPrize / numberOfWinners;

        // Select winners and distribute prizes
        for (uint i = 0; i < numberOfWinners; i++) {
            winners[i] = selectRandomWinner();
            bool winnerExists = false;
            for (uint j = 0; j < pastWinners.length; j++) {
                if (pastWinners[j].userAddress == winners[i]) {
                    // If winner already exists, increment their wins
                    pastWinners[j].wins += 1;
                    winnerExists = true;
                    break;
                }
            }
            if (!winnerExists) {
                // if winner does not exist then add it
                pastWinners.push(PastWinners({
                    userAddress: winners[i],
                    wins: 1
                }));
            }

            if (winnerHistory.length >= last_X_Winners) {
                // remove the first winner when full (FIFO)
                for (uint k = 0; k < winnerHistory.length - 1; k++) {
                    winnerHistory[k] = winnerHistory[k + 1];
                }
                winnerHistory[winnerHistory.length - 1] = winners[i];
            } else {
                winnerHistory.push(winners[i]);
            }

            emit NewWinnerAdded(winners[i], pastWinners[pastWinners.length - 1].wins);

            emit WinnersGuy(winners[i]);
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
        uint winnerIndex = random % consumedTickets;
        uint counter = 0;

        // Iterate through participants to find winning ticket
        for (uint i = 0; i < participants.length; i++) {
            address participant = participants[i];
            uint participantTickets = ticketsBought[participant];
            
            // Check if winning index falls within this participant's ticket range
            if (winnerIndex >= counter && winnerIndex < counter + participantTickets) {
                // Remove used ticket
                // ticketsBought[participant]--;
                
                // If participant has no more tickets, remove from participants array
                // if (ticketsBought[participant] == 0) {
                //     participants[i] = participants[participants.length - 1];
                //     participants.pop();
                // }

                // remove all the previous winner ticket from the pot
                consumedTickets = consumedTickets - ticketsBought[participant];
                
                // remove winner to prevent duplicate winner selection
                participants[i] = participants[participants.length - 1];
                participants.pop();
                
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

    function getAvailableTickets() public view returns (uint) {
        return availableTickets;
    }

    function getConsumedTickets() public view returns (uint) {
        return consumedTickets;
    }

    function getWinnerHistory() public view returns (address[] memory) {
        return winnerHistory;
    }

    function getOverallAllHistoryWinners() public view returns (PastWinners[] memory) {
        return pastWinners;
    }

    // Modifier to restrict function access to contract owner
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
}