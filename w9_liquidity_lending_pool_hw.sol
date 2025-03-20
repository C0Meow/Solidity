// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract cw9_3_MockLendingPool {
    // Add collateral tracking
    mapping(address => uint256) public collaterals;  // Track collateral by address
    
    address public owner;
    uint256 interest_rate;
    mapping(address => uint256) public deposits;  // Track deposits by address
    mapping(address => uint256) public borrowings;  // Track borrowings by address
    uint256 public totalLiquidity;  // Total liquidity in the pool
    uint256 public interestRate = 5;  // 5% interest for simplicity

    uint256 public loanCounter; //tracks how many loans
    mapping(uint256 => Loan) public loans; //track loans by ID
    mapping(address => uint256[]) public userLoans; //track user's loan IDs
    address[] public depositors;
    uint256 public lastAccrualTimestamp;
    uint256 public accruedReward;
    uint256 public constant contractFeeFromRepayment = 1; //1%

    struct Loan {
        address borrower;         
        uint256 loanAmount;        
        uint256 interestRate;      
        uint256 repaymentAmount;   
        uint256 repaymentTimestamp ;
        bool isRepaid;             
        bool isActive;         
    }

    constructor(uint256 _interest_rate) {
        owner = msg.sender;
        interest_rate = _interest_rate;
        lastAccrualTimestamp = block.timestamp;
    }

    event Deposit(address indexed lender, uint256 amount);
    event Borrow(address indexed borrower, uint256 amount, uint256 collateral);
    event Repay(address indexed borrower, uint256 amount, uint256 collateralReturned);
    event Liquidate(address indexed borrower, uint256 collateralSeized, uint256 debtCleared);
    event LoanTaken(address indexed borrower, uint256 loanCounter, uint256 amount);
    event LoanRepaid(address indexed borrower, uint256 loanId, uint256 amount);
    event Withdrawal(address indexed withdrawer, uint256 withdrawAmount);
    event InterestAccrued(uint256 interestAmount, uint256 newTotalLiquidity, uint256 timestamp);
    event FeeDistributed(address indexed distributedTo, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can perform this action");
        _;
    }

    function deposit() external payable {
        require(msg.value > 0, "Deposit amount must be greater than 0");
        deposits[msg.sender] += msg.value;
        totalLiquidity += msg.value;
        emit Deposit(msg.sender, msg.value);
        depositors.push(msg.sender);
    }

    function isDepositor(address a) public view returns (bool){
        for (uint256 i = 0; i < depositors.length ; ++i) { //iterates through array depositor
            if (depositors[i] == a){ 
                return true;  
            }
        }
        return false;
    }

    function findDepositorIndex(address a) internal view returns (bool, uint256) {
        for (uint256 i = 0; i < depositors.length; i++) {
            if (depositors[i] == a) {
                return (true, i);
            }
        }
        return (false, 0);
    }

    function withdraw(uint256 withdrawAmount) external payable{
        //Check
        require(isDepositor(msg.sender), "You are not a depositor.");
        require(withdrawAmount <= deposits[msg.sender], "You don't have this much amount of deposit to withdraw");
        require(withdrawAmount <= totalLiquidity, "Not enough liquidity in pool");

        //Effect
        deposits[msg.sender] -= withdrawAmount;
        totalLiquidity -= withdrawAmount;

        //Interact
        (bool success, ) = payable(msg.sender).call{value: withdrawAmount}("");
        require(success, "Withdrawal transfer failed");
        
        if (deposits[msg.sender] == 0) { //removeProvider when their balance becomes zero.
            (bool exists, uint256 index) = findDepositorIndex(msg.sender);
            if (exists) {
                depositors[index] = depositors[depositors.length - 1];
                depositors.pop();
            }
        }

        emit Withdrawal(msg.sender, withdrawAmount);
    }

    function borrow(uint256 amount) external payable {
        require(amount > 0, "Borrow amount must be greater than 0");
        require(amount <= totalLiquidity, "Not enough liquidity in the pool");
        require(msg.value >= (amount * 150) / 100, "Collateral must be 150% of the loan amount");

        // Store collateral
        collaterals[msg.sender] = msg.value;  // Store exact collateral amount
        borrowings[msg.sender] = amount;      // Store exact borrowed amount
        totalLiquidity -= amount;

        // Send borrowed amount to the borrower
        payable(msg.sender).transfer(amount);

        emit Borrow(msg.sender, amount, msg.value);
    }

    function repay() external payable {
        require(borrowings[msg.sender] > 0, "You have no outstanding loans");
        
        uint256 interest = (borrowings[msg.sender] * interestRate) / 100;
        uint256 totalRepayment = borrowings[msg.sender] + interest;
        require(msg.value >= totalRepayment, "Include interest in the repayment");

        uint256 collateralToReturn = collaterals[msg.sender];
        require(collateralToReturn > 0, "No collateral to return");

        // Update state before transfers
        totalLiquidity += borrowings[msg.sender];
        borrowings[msg.sender] = 0;
        collaterals[msg.sender] = 0;

        // Return collateral to borrower
        (bool success, ) = payable(msg.sender).call{value: collateralToReturn}("");
        require(success, "Failed to return collateral");

        emit Repay(msg.sender, msg.value, collateralToReturn);
    }

    function liquidate(address borrower) external onlyOwner {
        require(borrowings[borrower] > 0, "No active loans for this borrower");
        
        uint256 debtAmount = borrowings[borrower];
        uint256 collateralAmount = collaterals[borrower];
        require(collateralAmount > 0, "No collateral to seize");

        // Clear borrower's state before transfer
        borrowings[borrower] = 0;
        collaterals[borrower] = 0;

        // Transfer seized collateral to owner
        (bool success, ) = payable(owner).call{value: collateralAmount}("");
        require(success, "Failed to transfer collateral to owner");

        // Add the debt back to total liquidity
        totalLiquidity += debtAmount;

        emit Liquidate(borrower, collateralAmount, debtAmount);
    }

    function getCollateral(address borrower) external view returns (uint256) {
        return collaterals[borrower];
    }

    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    // Add function to check all balances
    function getBalances(address account) external view returns (
        uint256 depositBalance,
        uint256 borrowBalance,
        uint256 collateralBalance
    ) {
        return (
            deposits[account],
            borrowings[account],
            collaterals[account]
        );
    }

    function takeLoan(uint256 amount, uint256 loan_duration) external payable {
        require(amount > 0, "Loan amount must be greater than 0");
        require(amount <= totalLiquidity, "Not enough liquidity in pool");
        require(msg.value >= (amount * 150) / 100, "Collateral must be 150% of loan amount");

        // Calculate repayment details
        //uint256 interest = (amount * interest_rate) / 100;
        uint256 repaymentAmount = requiredRepaymentAmount(amount);
        uint256 repaymentTime = block.timestamp + loan_duration * 86400; //converting days to seconds

        // Create new loan
        loanCounter++;
        loans[loanCounter] = Loan({
            borrower: msg.sender,
            loanAmount: amount,
            interestRate: interest_rate,
            repaymentAmount: repaymentAmount,
            repaymentTimestamp: repaymentTime,
            isRepaid: false,
            isActive: true
        });

        // Update tracking
        userLoans[msg.sender].push(loanCounter);
        collaterals[msg.sender] += msg.value;
        totalLiquidity -= amount;

        // Transfer loan amount to borrower
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Loan transfer failed");

        emit LoanTaken(msg.sender, loanCounter, amount);
    }

    function repayLoan(uint256 loanId) external payable {
        Loan storage loan = loans[loanId];
        //Check
        require(loan.borrower == msg.sender, "Not your loan");
        require(loan.isActive, "Loan is not active");
        require(!loan.isRepaid, "Loan already repaid");
        require(msg.value >= loan.repaymentAmount, "Insufficient repayment amount");

        uint256 fee = (loan.repaymentAmount * contractFeeFromRepayment) / 100; //Amount we earned, case 1's 0.525eth
        uint256 amountToPool = loan.repaymentAmount - fee; // Amount back to the pool
        accruedReward += fee; //later distribute it to the depositors

        // Update state
        loan.isRepaid = true;
        loan.isActive = false;
        uint256 collateralToReturn = collaterals[msg.sender];
        require(collateralToReturn > 0, "No collateral to return");
        collaterals[msg.sender] = 0;
        totalLiquidity += amountToPool; 
        
        // Update status; Effect
        loan.isRepaid = true;
        loan.isActive = false;

        // Return collateral to borrower; Interact
        (bool success, ) = payable(msg.sender).call{value: collateralToReturn}("");
        require(success, "Failed to return collateral");

        emit LoanRepaid(msg.sender, loanId, msg.value);
    }

    function accrueInterest() external {
        require(totalLiquidity > 0, "No liquidity to accrue interest on");

        // Calculate time elapsed since last accrual in seconds
        uint256 timeElapsed = block.timestamp - lastAccrualTimestamp;
        if (timeElapsed == 0) return; // No interest if no time has passed

        
        uint256 secondsPerYear = 365 * 24 * 60 * 60; //31,536,000 sec, compound yearly
        //interest = principal(total liquidity pool) * interest_rate * yearly) / (100 * secondsPerYear)
        uint256 interest = (totalLiquidity * interest_rate * timeElapsed) / (100 * secondsPerYear);


        if (interest > 0) {
            accruedReward += interest; //put it into accrued reward to distribute it later
            lastAccrualTimestamp = block.timestamp; //update the last accrue time
            emit InterestAccrued(interest, totalLiquidity, block.timestamp);
        }
    }

    // Helper function to calculate a user's share of the pool
    function calculateFeeShare(address user) public view returns (uint256) {
        if (totalLiquidity == 0) return 0;
        return (deposits[user] * accruedReward) / totalLiquidity;
    }
    // Check Accrued Fees
    function getUserAccruedFees(address user) public view returns (uint256) {
        return accruedReward * calculateFeeShare(user);
    }

    function distributeFees() external payable onlyOwner{
        require(accruedReward > 0, "No fees to distribute");
        uint256 totalDistributed = 0;
        for (uint256 i = 0; i < depositors.length; i++) {
            address depositor = depositors[i];
            uint256 share = calculateFeeShare(depositor); 
            if (share > 0) {
                totalDistributed += share;
                (bool success, ) = payable(depositor).call{value: share}("");
                require(success, "Fee distribution failed");
                emit FeeDistributed(depositor, share);
            }
        }

        accruedReward -= totalDistributed;
    }

    function calculateRepaymentAmount(uint256 loanId) public view returns (uint256) {
        Loan memory loan = loans[loanId];
        require(loan.loanAmount > 0, "Loan does not exist or has no amount");
        return loan.repaymentAmount;
    }

    function getLiquidityPool() public view returns (uint256){
        return totalLiquidity;
    }

    function getUserBalance(address a) public view returns (uint256){
        require(isDepositor(a), "Not a depositor.");
        return deposits[a];
    }

    function getLiquidityPoolWithLoan() public view returns (uint256) { //Liquidity pool that includes outstanding loan too
        uint256 borrowed = 0;
        for (uint256 i = 1; i <= loanCounter; i++) {
            if (loans[i].isActive && !loans[i].isRepaid) {
                borrowed += loans[i].loanAmount;
            }
        }
        return totalLiquidity + borrowed;
    }

    function requiredCollateral(uint256 loan) public pure returns (uint256) {
        require(loan > 0, "Loan amount must be > 0");
        return (loan * 150) / 100;
    }

    function requiredRepaymentAmount(uint256 loan) public view returns (uint256) {
    require(loan > 0, "Loan amount must be > 0");
    uint256 interest = (loan * interest_rate) / 100;
    return loan + interest;
}


    receive() external payable {}
}