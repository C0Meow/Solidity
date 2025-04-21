// Remix script to deploy contract and call setFeePercentage
(async () => {
    try {
        // 1. Get the accounts from Remix environment
        const accounts = await ethers.getSigners();
        const deployer = accounts[0];

        // 2. Deploy the contract
        console.log("Deploying FeeContract...");
        const FeeContract = await ethers.getContractFactory("FeeContract");
        const contract = await FeeContract.deploy();
        await contract.deployed();
        console.log("Contract deployed at:", contract.address);

        // 3. Your provided lines
        const abi = ["function setFeePercentage(uint256 newFeePercentage)"];
        const iface = new ethers.utils.Interface(abi);
        const callData = iface.encodeFunctionData("setFeePercentage", [500]); // 5%

        // 4. Send the transaction using the encoded call data
        console.log("Calling setFeePercentage with 5% (500)...");
        const tx = await deployer.sendTransaction({
            to: contract.address,
            data: callData
        });
        await tx.wait();
        console.log("Transaction hash:", tx.hash);

        // 5. Verify the result
        const newFee = await contract.feePercentage();
        console.log("New fee percentage:", newFee.toString());

    } catch (error) {
        console.error("Error:", error);
    }
})();