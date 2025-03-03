// SPDX-License-Identifier: GPL-3.0
        
pragma solidity >=0.4.22 <0.9.0;

// This import is automatically injected by Remix
import "remix_tests.sol"; 

// This import is required to use custom transaction context
// Although it may fail compilation in 'Solidity Compiler' plugin
// But it will work fine in 'Solidity Unit Testing' plugin
import "remix_accounts.sol";
import "../contracts/w6_SupplyChainContractAsm.sol";

// File name has to end with '_test.sol', this file can contain more than one testSuite contracts
contract SupplyChainTest {
    SupplyChainContract supplyChain;
    address owner;
    address authorized1;
    address authorized2;
    address unauthorized;

    function beforeAll() public {
        owner = TestsAccounts.getAccount(0);
        authorized1 = TestsAccounts.getAccount(1);
        authorized2 = TestsAccounts.getAccount(2);
        unauthorized = TestsAccounts.getAccount(3);

        supplyChain = new SupplyChainContract();
        supplyChain.authorizeParticipant(owner);
        
        //supplyChain.authorizeParticipant(owner);
        supplyChain.authorizeParticipant(authorized1);
        supplyChain.authorizeParticipant(authorized2);
    }

    function testAuthorization() public {
        Assert.ok(
            supplyChain.authorizedParticipants(authorized1),
            "Authorized1 should be authorized"
        );
        Assert.ok(
            supplyChain.authorizedParticipants(authorized2),
            "Authorized2 should be authorized"
        );
        Assert.ok(
            !supplyChain.authorizedParticipants(unauthorized),
            "Unauthorized should not be authorized"
        );
    }

    /// #sender: account-1
    function testIndividualRegistration() public {
        supplyChain.registerProduct("iphone10", "1024GB");
        (uint id, string memory name, , , bool recalled) = supplyChain.getProduct(1);
        
        Assert.equal(id, 1, "productId should be 1");
        Assert.equal(name, "iphone10", "product name mismatch");
        Assert.ok(!recalled, "should not be recalled yet");
        Assert.equal(supplyChain.productCount(), 1, "this individual reg should only have 1 product only");
    }

    function testRegisterEmptyDescription() public {
        try supplyChain.registerProduct("iphonenodesc", "") {
            Assert.ok(false, "empty description shouldnt be allowed");
        } catch {
            Assert.ok(true, "Blocked register product with empty description");
        }
    }
        
    /// #sender: account-1
    function testRegisterEmptyName() public {
        try supplyChain.registerProduct("", "iphonenoname") {
            Assert.ok(false, "empty name shouldnt be allowed");
        } catch {
            Assert.ok(true, "Blocked register product with empty name");
        }
    }

    /// #sender: account-1
    function testOwnershipTransfer() public {
        supplyChain.transferProductOwnership(1, authorized2);
        (,,address currentOwner,,) = supplyChain.getProduct(1);
        Assert.equal(currentOwner, authorized2, "Ownership transfer failed");
    }

    /// #sender: account-1
    function testOwnershipTransferToZeroAddress() public {
        try supplyChain.transferProductOwnership(1, address(0)) {
            Assert.ok(false, "shouldnt allow transfer to 0 address");
        } catch {
            Assert.ok(true, "Blocked transferring to 0 address");
        }
    }

    /// #sender: account-2
    function testSelfOwnershipTransfer() public {
        try supplyChain.transferProductOwnership(1, authorized2) {
            Assert.ok(false, "shouldnt allow transfer to yourself");
        } catch {
            Assert.ok(true, "Blocked transferring to yourself");
        }
    }

    /// #sender: account-1
    function testProductRecall() public {
        supplyChain.recallProduct(1, "test indi recall");
        (,,,,bool recalled) = supplyChain.getProduct(1);
        Assert.ok(recalled, "indi recall failed");
    }

    function testProductRecallNonExistingProduct() public {
        try supplyChain.recallProduct(9, "test indi recall non existing product") {
            Assert.ok(false, "shouldnt allow recall nonexisting product");
        } catch {
            Assert.ok(true, "Blocked recall nonexisting product");
        }
    }

    function testProductRecallAlreadyRecalled() public {
        try supplyChain.recallProduct(1, "test recall already recalled product") {
            Assert.ok(false, "shouldnt allow recall recalled product");
        } catch {
            Assert.ok(true, "Blocked recalling recalled product");
        }
    }


    /// #sender: account-1
    function testBatchRegistration() public {
        string[] memory names = new string[](2);
        names[0] = "iphone8";
        names[1] = "iphone9";
        string[] memory descs = new string[](2);
        descs[0] = "256GB";
        descs[1] = "512GB";
        uint256[] memory emptyIds = new uint256[](0);

        supplyChain.createBatch(emptyIds, names, descs, "registerBatch");
        supplyChain.processBatch(1, authorized1, "registerBatch", "");

        (uint256[] memory batchIds, , , , , , ,) = supplyChain.getBatch(1);
        Assert.equal(batchIds.length, 2, "batch should contain 2 products only");
        //Assert.equal(batchIds[0], 2, "id isnt 2");
        //Assert.equal(batchIds[1], 3, "id isnt 3");
        Assert.equal(supplyChain.productCount(), 3, "total products should be 3, 2 from batch 1 from individual");
    }

    /// #sender: account-1
    function testBatchRegisterEmptyName() public {
        string[] memory names = new string[](2);
        names[0] = "";
        names[1] = "";
        string[] memory descs = new string[](2);
        descs[0] = "256GB";
        descs[1] = "512GB";
        uint256[] memory emptyIds = new uint256[](0);

        try supplyChain.createBatch(emptyIds, names, descs, "registerBatch") {
            Assert.ok(false, "empty name shouldnt be allowed");
        } catch {
            Assert.ok(true, "Blocked register product with empty name");
        }
    }

    /// #sender: account-1
    function testBatchRegisterEmptyDesc() public {
        string[] memory names = new string[](2);
        names[0] = "ipnodesc";
        names[1] = "ipnodesc2";
        string[] memory descs = new string[](2);
        descs[0] = "";
        descs[1] = "";
        uint256[] memory emptyIds = new uint256[](0);
        
        try supplyChain.createBatch(emptyIds, names, descs, "registerBatch") {
            Assert.ok(false, "empty desc shouldnt be allowed");
        } catch {
            Assert.ok(true, "Blocked register product with empty desc");
        }
    }


    /// #sender: account-1
    function testBatchTransfer() public {
        supplyChain.processBatch(1, authorized2, "transferBatch", "transferBatch");

        (,,address owner1,,) = supplyChain.getProduct(2);
        (,,address owner2,,) = supplyChain.getProduct(3);
        Assert.equal(owner1, authorized2, "Batch transfer failed for product 2");
        Assert.equal(owner2, authorized2, "Batch transfer failed for product 3");
    }

    /// #sender: account-1
    function testBatchZeroAddressOwnershipTransfer() public {
        try supplyChain.processBatch(1, address(0), "transferBatch", "transferBatch") {
            Assert.ok(false, "shouldnt allow transferring to 0 address");
        } catch {
            Assert.ok(true, "Blocked transferring to 0 address");
        }
    }

    /// #sender: account-1
    function testBatchSelfOwnershipTransfer() public {
        try supplyChain.processBatch(1, authorized1, "transferBatch", "transferBatch") {
            Assert.ok(false, "shouldnt allow transferring to yourself");
        } catch {
            Assert.ok(true, "Blocked transferring to yourself");
        }
    }

    /// #sender: account-1
    function testBatchRecall() public {
        
        supplyChain.processBatch(1, authorized1, "recallBatch", "test batch recall");

        (,,,,bool recalled1) = supplyChain.getProduct(2);
        (,,,,bool recalled2) = supplyChain.getProduct(3);
        Assert.ok(recalled1, "iphone8 recall failed");
        Assert.ok(recalled2, "iphone9 recall failed");
        
        (,,,,,bool batchRecalled,,) = supplyChain.getBatch(1);
        Assert.ok(batchRecalled, "batch recall failed");
    }

    function testBatchRecallAlreadyRecalled() public {
        try supplyChain.processBatch(1, authorized2, "reacllBatch", "reacllBatch") {
            Assert.ok(false, "shouldnt allow already recalled batch to recall");
        } catch {
            Assert.ok(true, "Blocked recalled batch to be recalled again");
        }
    }

    /// #sender: account-1
    function testInvalidTransfer() public {
        (bool success, ) = address(supplyChain).call(
            abi.encodeWithSignature("transferProductOwnership(uint256,address)", 99, authorized2)
        );
        Assert.ok(!success, "Invalid productId should fail");
    }

    function testReentryRecall() public {
        /// #sender: account-1
        (bool success, ) = address(supplyChain).call(
            abi.encodeWithSignature("recallProduct(uint256,string)", 1, "reentry recall")
        );
        Assert.ok(!success, "reentry recall should fail");
    }
}