// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {SafeTransferLib, ERC20} from "solmate/utils/SafeTransferLib.sol";
import {IFlywheelRewards} from "../interfaces/IFlywheelRewards.sol";

/** 
 @title Flywheel Dynamic Reward Stream
 @notice Determines rewards based on how many reward tokens appeared in the market itself since last accrual.
 All rewards are transferred atomically, so there is no need to use the last reward timestamp.
*/ 
contract FlywheelDynamicRewards is IFlywheelRewards {
    using SafeTransferLib for ERC20;

    /// @notice the reward token paid
    ERC20 public immutable rewardToken;

    /// @notice the flywheel core contract
    address public immutable flywheel;

    constructor(ERC20 _rewardToken, address _flywheel) {
        rewardToken = _rewardToken;
        flywheel = _flywheel;
    }

    /**
     @notice calculate and transfer accrued rewards to flywheel core
     @param market the market to accrue rewards for
     @return amount the amount of tokens accrued and transferred
     */
    function getAccruedRewards(ERC20 market, uint32) external override returns (uint256 amount) {
        require(msg.sender == flywheel, "!flywheel");
        amount = rewardToken.balanceOf(address(market));
        if (amount > 0) rewardToken.safeTransferFrom(address(market), flywheel, amount);
    }
}
