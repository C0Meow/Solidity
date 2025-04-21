const abi = ["function setFeePercentage(uint256 newFeePercentage)"]; 

const iface = new ethers.utils.Interface(abi); 

const callData = iface.encodeFunctionData("setFeePercentage", [500]); // 5% 