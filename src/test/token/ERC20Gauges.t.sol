// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {MockERC20Gauges} from "../mocks/MockERC20Gauges.sol";

contract ERC20GaugesTest is DSTestPlus {

    MockERC20Gauges token;
    address constant gauge1 = address(0xDEAD);
    address constant gauge2 = address(0xBEEF);

    function setUp() public {
        token = new MockERC20Gauges(address(this), 3600); // 1 hour cycles
        token.mint(address(this), 100e18);
    }

    /*///////////////////////////////////////////////////////////////
                        TEST ADMIN GAUGE OPERATIONS
    //////////////////////////////////////////////////////////////*/

    function testSetMaxGauges() public {
        token.setMaxGauges(2);
        require(token.maxGauges() == 2);
    }

    function testSetMaxGaugesNonOwner() public {
        hevm.prank(address(1));
        hevm.expectRevert(bytes("UNAUTHORIZED"));
        token.setMaxGauges(2);
    }

    function testCanContractExceedMax() public {
        token.setContractExceedMax(address(this), true);
        require(token.canContractExceedMax(address(this)));
    }

    function testCanContractExceedMaxNonOwner() public {
        hevm.prank(address(1));
        hevm.expectRevert(bytes("UNAUTHORIZED"));
        token.setContractExceedMax(address(this), true);
    }

    function testCanContractExceedMaxNonContract() public {
        hevm.expectRevert(abi.encodeWithSignature("NonContractError()"));
        token.setContractExceedMax(address(1), true);
    }

    function testAddGauge() public {
        token.setMaxGauges(2);
        token.addGauge(gauge1);
        require(token.numGauges() == 1);
        require(token.gauges()[0] == gauge1);

        token.addGauge(gauge2);
        require(token.numGauges() == 2);
        require(token.gauges()[0] == gauge1);
        require(token.gauges()[1] == gauge2);
    }

    function testAddPreviouslyDeprecated() public {
        token.setMaxGauges(2);
        token.addGauge(gauge1);
        token.incrementGauge(gauge1, 1e18);

        token.removeGauge(gauge1);
        token.addGauge(gauge1);

        require(token.numGauges() == 1);
        require(token.totalWeight() == 1e18);
        require(token.getGaugeWeight(gauge1) == 1e18);
        require(token.getUserGaugeWeight(address(this), gauge1) == 1e18);  
        require(token.deprecatedGauges().length == 0);
    }

    function testAddGaugeTwice() public {
        token.setMaxGauges(2);
        token.addGauge(gauge1);
        hevm.expectRevert(abi.encodeWithSignature("InvalidGaugeError()"));
        token.addGauge(gauge1);
    }

    function testAddGaugeNonOwner() public {
        token.setMaxGauges(1);
        hevm.prank(address(1));
        hevm.expectRevert(bytes("UNAUTHORIZED"));
        token.addGauge(gauge1);
    }

    function testRemoveGauge() public {
        token.setMaxGauges(2);
        token.addGauge(gauge1);
        token.removeGauge(gauge1);
        require(token.numGauges() == 0);
        require(token.deprecatedGauges()[0] == gauge1);
    }

    function testRemoveGaugeTwice() public {
        token.setMaxGauges(2);
        token.addGauge(gauge1);
        token.removeGauge(gauge1);
        hevm.expectRevert(abi.encodeWithSignature("InvalidGaugeError()"));
        token.removeGauge(gauge1);
    }

    function testRemoveGaugeNonOwner() public {
        token.setMaxGauges(2);
        token.addGauge(gauge1);
        hevm.startPrank(address(1));
        hevm.expectRevert(bytes("UNAUTHORIZED"));
        token.removeGauge(gauge1);
    }

    function testRemoveGaugeWithWeight() public {
        token.setMaxGauges(2);
        token.addGauge(gauge1);
        token.incrementGauge(gauge1, 1e18);

        token.removeGauge(gauge1);
        require(token.numGauges() == 0);
        require(token.totalWeight() == 0);
        require(token.getGaugeWeight(gauge1) == 1e18);
        require(token.getUserGaugeWeight(address(this), gauge1) == 1e18);
    }

    function testReplaceGauge() public {
        token.setMaxGauges(2);
        token.addGauge(gauge1);    
        token.replaceGauge(gauge1, gauge2);   
        require(token.numGauges() == 1);
        require(token.gauges()[0] == gauge2); 
        require(token.deprecatedGauges()[0] == gauge1); 
    }

    function testReplaceGaugeNonOwner() public {
        token.setMaxGauges(2);
        token.addGauge(gauge1);
        hevm.startPrank(address(1));
        hevm.expectRevert(bytes("UNAUTHORIZED"));
        token.replaceGauge(gauge1, gauge2);   
    }

    /*///////////////////////////////////////////////////////////////
                        TEST USER GAUGE OPERATIONS
    //////////////////////////////////////////////////////////////*/

    function testCalculateGaugeAllocation() public {
        token.setMaxGauges(2);
        token.addGauge(gauge1);
        token.addGauge(gauge2);

        require(token.incrementGauge(gauge1, 1e18) == 1e18);
        require(token.incrementGauge(gauge2, 1e18) == 2e18);

        hevm.warp(3600); // warp 1 hour to store changes
        require(token.calculateGaugeAllocation(gauge1, 100e18) == 50e18);
        require(token.calculateGaugeAllocation(gauge2, 100e18) == 50e18);

        require(token.incrementGauge(gauge2, 2e18) == 4e18);

        // ensure updates don't propagate until stored
        require(token.calculateGaugeAllocation(gauge1, 100e18) == 50e18);
        require(token.calculateGaugeAllocation(gauge2, 100e18) == 50e18);

        hevm.warp(7200); // warp another hour to store changes again
        require(token.calculateGaugeAllocation(gauge1, 100e18) == 25e18);
        require(token.calculateGaugeAllocation(gauge2, 100e18) == 75e18);
    }

    /// @notice test incrementing different gauges 4 times by multiple users and weights
    function testIncrement() public {
        token.setMaxGauges(2);
        token.addGauge(gauge1);
        token.addGauge(gauge2);

        // gauge1,user1 +1
        require(token.incrementGauge(gauge1, 1e18) == 1e18);
        require(token.getUserGaugeWeight(address(this), gauge1) == 1e18);
        require(token.getUserWeight(address(this)) == 1e18);
        require(token.getGaugeWeight(gauge1) == 1e18);
        require(token.totalWeight() == 1e18);

        // gauge2,user1 +2
        require(token.incrementGauge(gauge2, 2e18) == 3e18);
        require(token.getUserGaugeWeight(address(this), gauge2) == 2e18);
        require(token.getUserWeight(address(this)) == 3e18);
        require(token.getGaugeWeight(gauge2) == 2e18);
        require(token.totalWeight() == 3e18);

        // gauge1,user1 +4
        require(token.incrementGauge(gauge1, 4e18) == 7e18);
        require(token.getUserGaugeWeight(address(this), gauge1) == 5e18);
        require(token.getUserWeight(address(this)) == 7e18);
        require(token.getGaugeWeight(gauge1) == 5e18);
        require(token.totalWeight() == 7e18);

        // gauge2,user2 +3
        hevm.startPrank(address(1));
        token.mint(address(1), 10e18);

        require(token.incrementGauge(gauge2, 3e18) == 3e18);
        require(token.getUserGaugeWeight(address(1), gauge2) == 3e18);
        require(token.getUserWeight(address(1)) == 3e18);
        require(token.getGaugeWeight(gauge2) == 5e18);
        require(token.totalWeight() == 10e18);
    }   

    /// @notice test incrementing over user max
    function testIncrementOverMax() public {
        token.setMaxGauges(1);
        token.addGauge(gauge1);
        token.addGauge(gauge2);

        token.incrementGauge(gauge1, 1e18);
        hevm.expectRevert(abi.encodeWithSignature("MaxGaugeError()"));
        token.incrementGauge(gauge2, 1e18);
    }

    /// @notice test incrementing at user max
    function testIncrementAtMax() public {
        token.setMaxGauges(1);
        token.addGauge(gauge1);
        token.addGauge(gauge2);

        token.incrementGauge(gauge1, 1e18);
        token.incrementGauge(gauge1, 1e18);

        require(token.getUserGaugeWeight(address(this), gauge1) == 2e18);
        require(token.getUserWeight(address(this)) == 2e18);
        require(token.getGaugeWeight(gauge1) == 2e18);
        require(token.totalWeight() == 2e18);
    }

    /// @notice test incrementing over user max
    function testIncrementOverMaxApproved() public {
        token.setMaxGauges(1);
        token.addGauge(gauge1);
        token.addGauge(gauge2);

        token.incrementGauge(gauge1, 1e18);
        token.setContractExceedMax(address(this), true);
        token.incrementGauge(gauge2, 1e18);

        require(token.getUserGaugeWeight(address(this), gauge1) == 1e18);
        require(token.getUserGaugeWeight(address(this), gauge2) == 1e18);
        require(token.getUserWeight(address(this)) == 2e18);
        require(token.getGaugeWeight(gauge1) == 1e18);
        require(token.getGaugeWeight(gauge2) == 1e18);
        require(token.totalWeight() == 2e18);
    }

    /// @notice test incrementing and make sure weights are stored
    function testIncrementWithStorage() public {
        token.setMaxGauges(2);
        token.addGauge(gauge1);
        token.addGauge(gauge2);

        // gauge1,user1 +1
        require(token.incrementGauge(gauge1, 1e18) == 1e18);
        require(token.getUserGaugeWeight(address(this), gauge1) == 1e18);
        require(token.getUserWeight(address(this)) == 1e18);
        require(token.getGaugeWeight(gauge1) == 1e18);
        require(token.totalWeight() == 1e18);

        require(token.getStoredGaugeWeight(gauge1) == 0);
        require(token.storedTotalWeight() == 0);

        hevm.warp(block.timestamp + 3600); // warp one cycle

        require(token.getStoredGaugeWeight(gauge1) == 1e18);
        require(token.storedTotalWeight() == 1e18);

        // gauge2,user1 +2
        require(token.incrementGauge(gauge2, 2e18) == 3e18);
        require(token.getUserGaugeWeight(address(this), gauge2) == 2e18);
        require(token.getUserWeight(address(this)) == 3e18);
        require(token.getGaugeWeight(gauge2) == 2e18);
        require(token.totalWeight() == 3e18);

        require(token.getStoredGaugeWeight(gauge2) == 0);
        require(token.storedTotalWeight() == 1e18);

        hevm.warp(block.timestamp + 1800); // warp half cycle

        require(token.getStoredGaugeWeight(gauge2) == 0);
        require(token.storedTotalWeight() == 1e18);

        // gauge1,user1 +4
        require(token.incrementGauge(gauge1, 4e18) == 7e18);
        require(token.getUserGaugeWeight(address(this), gauge1) == 5e18);
        require(token.getUserWeight(address(this)) == 7e18);
        require(token.getGaugeWeight(gauge1) == 5e18);
        require(token.totalWeight() == 7e18);

        hevm.warp(block.timestamp + 1800); // warp half cycle

        require(token.getStoredGaugeWeight(gauge1) == 5e18);
        require(token.getStoredGaugeWeight(gauge2) == 2e18);
        require(token.storedTotalWeight() == 7e18);

        hevm.warp(block.timestamp + 3600); // warp full cycle

        require(token.getStoredGaugeWeight(gauge1) == 5e18);
        require(token.getStoredGaugeWeight(gauge2) == 2e18);
        require(token.storedTotalWeight() == 7e18);
    }

    function testIncrementOnDeprecated() public {
        token.setMaxGauges(2);
        token.addGauge(gauge1);
        token.removeGauge(gauge1);
        hevm.expectRevert(abi.encodeWithSignature("InvalidGaugeError()"));
        token.incrementGauge(gauge1, 1e18);
    }

    function testIncrementOverWeight() public {
        token.setMaxGauges(2);
        token.addGauge(gauge1);
        token.addGauge(gauge2);

        require(token.incrementGauge(gauge1, 50e18) == 50e18);
        hevm.expectRevert(abi.encodeWithSignature("OverWeightError()"));   
        token.incrementGauge(gauge2, 51e18);
    }

    
    /// @notice test incrementing multiple gauges with different weights after already incrementing once
    function testIncrementGauges() public {
        token.setMaxGauges(2);
        token.addGauge(gauge1);
        token.addGauge(gauge2);

        token.incrementGauge(gauge1, 1e18);

        address[] memory gaugeList = new address[](2);
        uint112[] memory weights = new uint112[](2);
        gaugeList[0] = gauge2;
        gaugeList[1] = gauge1;
        weights[0] = 2e18;
        weights[1] = 4e18;

        require(token.incrementGauges(gaugeList, weights) == 7e18);

        require(token.getUserGaugeWeight(address(this), gauge2) == 2e18);
        require(token.getGaugeWeight(gauge2) == 2e18);
        require(token.getUserGaugeWeight(address(this), gauge1) == 5e18);
        require(token.getUserWeight(address(this)) == 7e18);
        require(token.getGaugeWeight(gauge1) == 5e18);
        require(token.totalWeight() == 7e18);
    }

    function testIncrementGaugesDeprecated() public {
        token.setMaxGauges(2);
        token.addGauge(gauge1);
        token.addGauge(gauge2);
        token.removeGauge(gauge2);

        address[] memory gaugeList = new address[](2);
        uint112[] memory weights = new uint112[](2);
        gaugeList[0] = gauge2;
        gaugeList[1] = gauge1;
        weights[0] = 2e18;
        weights[1] = 4e18;
        hevm.expectRevert(abi.encodeWithSignature("InvalidGaugeError()"));
        token.incrementGauges(gaugeList, weights);    
    }

    function testIncrementGaugesOver() public {
        token.setMaxGauges(2);
        token.addGauge(gauge1);
        token.addGauge(gauge2);

        address[] memory gaugeList = new address[](2);
        uint112[] memory weights = new uint112[](2);
        gaugeList[0] = gauge2;
        gaugeList[1] = gauge1;
        weights[0] = 50e18;
        weights[1] = 51e18;
        hevm.expectRevert(abi.encodeWithSignature("OverWeightError()"));
        token.incrementGauges(gaugeList, weights);    
    }

    function testIncrementGaugesSizeMismatch() public {
        token.setMaxGauges(2);
        token.addGauge(gauge1);
        token.addGauge(gauge2);
        token.removeGauge(gauge2);

        address[] memory gaugeList = new address[](2);
        uint112[] memory weights = new uint112[](3);
        gaugeList[0] = gauge2;
        gaugeList[1] = gauge1;
        weights[0] = 1e18;
        weights[1] = 2e18;
        hevm.expectRevert(abi.encodeWithSignature("SizeMismatchError()"));
        token.incrementGauges(gaugeList, weights);    
    }

    /// @notice test decrement twice, 2 tokens each after incrementing by 4.
    function testDecrement() public {
        token.setMaxGauges(2);
        token.addGauge(gauge1);
        token.addGauge(gauge2);

        require(token.incrementGauge(gauge1, 4e18) == 4e18);

        require(token.decrementGauge(gauge1, 2e18) == 2e18);
        require(token.getUserGaugeWeight(address(this), gauge1) == 2e18);
        require(token.getUserWeight(address(this)) == 2e18);
        require(token.getGaugeWeight(gauge1) == 2e18);
        require(token.totalWeight() == 2e18);

        require(token.decrementGauge(gauge1, 2e18) == 0);
        require(token.getUserGaugeWeight(address(this), gauge1) == 0);
        require(token.getUserWeight(address(this)) == 0);
        require(token.getGaugeWeight(gauge1) == 0);
        require(token.totalWeight() == 0);
    }   

    /// @notice test decrement all removes user gauge.
    function testDecrementAllRemovesGauge() public {
        token.setMaxGauges(2);
        token.addGauge(gauge1);
        token.addGauge(gauge2);

        require(token.incrementGauge(gauge1, 4e18) == 4e18);
        
        require(token.numUserGauges(address(this)) == 1);
        require(token.userGauges(address(this))[0] == gauge1);

        require(token.decrementGauge(gauge1, 4e18) == 0);

        require(token.numUserGauges(address(this)) == 0);
    }   

    /// @notice test decrement twice, 2 tokens each after incrementing by 4.
    function testDecrementWithStorage() public {
        token.setMaxGauges(2);
        token.addGauge(gauge1);
        token.addGauge(gauge2);

        require(token.incrementGauge(gauge1, 4e18) == 4e18);

        require(token.decrementGauge(gauge1, 2e18) == 2e18);
        require(token.getUserGaugeWeight(address(this), gauge1) == 2e18);
        require(token.getUserWeight(address(this)) == 2e18);
        require(token.getGaugeWeight(gauge1) == 2e18);
        require(token.totalWeight() == 2e18);

        require(token.getStoredGaugeWeight(gauge1) == 0);
        require(token.storedTotalWeight() == 0);

        hevm.warp(block.timestamp + 3600); // warp full cycle

        require(token.getStoredGaugeWeight(gauge1) == 2e18);
        require(token.storedTotalWeight() == 2e18);

        require(token.decrementGauge(gauge1, 2e18) == 0);
        require(token.getUserGaugeWeight(address(this), gauge1) == 0);
        require(token.getUserWeight(address(this)) == 0);
        require(token.getGaugeWeight(gauge1) == 0);
        require(token.totalWeight() == 0);

        require(token.getStoredGaugeWeight(gauge1) == 2e18);
        require(token.storedTotalWeight() == 2e18);

        hevm.warp(block.timestamp + 3600); // warp full cycle

        require(token.getStoredGaugeWeight(gauge1) == 0);
        require(token.storedTotalWeight() == 0);
    }

    function testDecrementOverWeight() public {
        token.setMaxGauges(2);
        token.addGauge(gauge1);
        token.addGauge(gauge2);

        require(token.incrementGauge(gauge1, 50e18) == 50e18);
        hevm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 17));
        token.decrementGauge(gauge1, 51e18);
    }

    function testDecrementGauges() public {
        token.setMaxGauges(2);
        token.addGauge(gauge1);
        token.addGauge(gauge2);

        token.incrementGauge(gauge1, 1e18);

        address[] memory gaugeList = new address[](2);
        uint112[] memory weights = new uint112[](2);
        gaugeList[0] = gauge2;
        gaugeList[1] = gauge1;
        weights[0] = 2e18;
        weights[1] = 4e18;

        require(token.incrementGauges(gaugeList, weights) == 7e18);

        weights[1] = 2e18;
        require(token.decrementGauges(gaugeList, weights) == 3e18);

        require(token.getUserGaugeWeight(address(this), gauge2) == 0);
        require(token.getGaugeWeight(gauge2) == 0);
        require(token.getUserGaugeWeight(address(this), gauge1) == 3e18);
        require(token.getUserWeight(address(this)) == 3e18);
        require(token.getGaugeWeight(gauge1) == 3e18);
        require(token.totalWeight() == 3e18);
    }

    function testDecrementGaugesOver() public {
        token.setMaxGauges(2);
        token.addGauge(gauge1);
        token.addGauge(gauge2);

        address[] memory gaugeList = new address[](2);
        uint112[] memory weights = new uint112[](2);
        gaugeList[0] = gauge2;
        gaugeList[1] = gauge1;
        weights[0] = 5e18;
        weights[1] = 5e18;

        require(token.incrementGauges(gaugeList, weights) == 10e18); 

        weights[1] = 10e18;
        hevm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 17));
        token.decrementGauges(gaugeList, weights); 
    }

    function testDecrementGaugesSizeMismatch() public {
        token.setMaxGauges(2);
        token.addGauge(gauge1);
        token.addGauge(gauge2);

        address[] memory gaugeList = new address[](2);
        uint112[] memory weights = new uint112[](2);
        gaugeList[0] = gauge2;
        gaugeList[1] = gauge1;
        weights[0] = 1e18;
        weights[1] = 2e18;

        require(token.incrementGauges(gaugeList, weights) == 3e18); 
        hevm.expectRevert(abi.encodeWithSignature("SizeMismatchError()"));   
        token.decrementGauges(gaugeList, new uint112[](0));    
    }

    /*///////////////////////////////////////////////////////////////
                            TEST ERC20 LOGIC
    //////////////////////////////////////////////////////////////*/

    function testDecrementUntilFreeWhenFree() public {
        token.setMaxGauges(2);
        token.addGauge(gauge1);
        token.addGauge(gauge2);

        require(token.incrementGauge(gauge1, 10e18) == 10e18);
        require(token.incrementGauge(gauge2, 20e18) == 30e18);
        require(token.userUnusedWeight(address(this)) == 70e18);

        token.burn(address(this), 50e18);
        require(token.userUnusedWeight(address(this)) == 20e18);

        require(token.getUserGaugeWeight(address(this), gauge1) == 10e18);
        require(token.getUserWeight(address(this)) == 30e18);
        require(token.getGaugeWeight(gauge1) == 10e18);
        require(token.getUserGaugeWeight(address(this), gauge2) == 20e18);
        require(token.getGaugeWeight(gauge2) == 20e18);
        require(token.totalWeight() == 30e18);
    }

    function testDecrementUntilFreeSingle() public {
        token.setMaxGauges(2);
        token.addGauge(gauge1);
        token.addGauge(gauge2);

        require(token.incrementGauge(gauge1, 10e18) == 10e18);
        require(token.incrementGauge(gauge2, 20e18) == 30e18);
        require(token.userUnusedWeight(address(this)) == 70e18);

        token.transfer(address(1), 80e18);
        require(token.userUnusedWeight(address(this)) == 0);

        require(token.getUserGaugeWeight(address(this), gauge1) == 0);
        require(token.getUserWeight(address(this)) == 20e18);
        require(token.getGaugeWeight(gauge1) == 0);
        require(token.getUserGaugeWeight(address(this), gauge2) == 20e18);
        require(token.getGaugeWeight(gauge2) == 20e18);
        require(token.totalWeight() == 20e18);
    }

    function testDecrementUntilFreeDouble() public {
        token.setMaxGauges(2);
        token.addGauge(gauge1);
        token.addGauge(gauge2);

        require(token.incrementGauge(gauge1, 10e18) == 10e18);
        require(token.incrementGauge(gauge2, 20e18) == 30e18);
        require(token.userUnusedWeight(address(this)) == 70e18);

        token.approve(address(1), 100e18);
        hevm.prank(address(1));
        token.transferFrom(address(this), address(1), 90e18);

        require(token.userUnusedWeight(address(this)) == 10e18);

        require(token.getUserGaugeWeight(address(this), gauge1) == 0);
        require(token.getUserWeight(address(this)) == 0);
        require(token.getGaugeWeight(gauge1) == 0);
        require(token.getUserGaugeWeight(address(this), gauge2) == 0);
        require(token.getGaugeWeight(gauge2) == 0);
        require(token.totalWeight() == 0);
    }

    function testDecrementUntilFreeDeprecated() public {
        token.setMaxGauges(2);
        token.addGauge(gauge1);
        token.addGauge(gauge2);

        require(token.incrementGauge(gauge1, 10e18) == 10e18);
        require(token.incrementGauge(gauge2, 20e18) == 30e18);
        require(token.userUnusedWeight(address(this)) == 70e18);

        require(token.totalWeight() == 30e18);
        token.removeGauge(gauge1);
        require(token.totalWeight() == 20e18);

        token.burn(address(this), 100e18);

        require(token.userUnusedWeight(address(this)) == 0);

        require(token.getUserGaugeWeight(address(this), gauge1) == 0);
        require(token.getUserWeight(address(this)) == 0);
        require(token.getGaugeWeight(gauge1) == 0);
        require(token.getUserGaugeWeight(address(this), gauge2) == 0);
        require(token.getGaugeWeight(gauge2) == 0);
        require(token.totalWeight() == 0);
    }
}