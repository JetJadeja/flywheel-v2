// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Auth, Authority} from "solmate/auth/Auth.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {IFlywheelRewards} from "./interfaces/IFlywheelRewards.sol";
import {IFlywheelBooster} from "./interfaces/IFlywheelBooster.sol";

/// @title Flywheel Core Incentives Manager
/// @author The Tribe
/// @notice Responsible for maintaining reward accrual through reward indexes.
/// It delegates the actual reward calculation accrual logic to the FlywheelRewards module.
contract FlywheelCore is Auth {
    using SafeTransferLib for ERC20;

    /*///////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice The token distributed among users.
    ERC20 public immutable rewardToken;

    /// @notice The fixed point factor of Flywheel.
    uint224 internal constant ONE = 1e18;

    /// @notice Creates a new FlywheelCore contract.
    /// @param _rewardToken The address of the token distributed among token holders.
    /// @param _flywheelRewards The address of the FlywheelRewards module contract.
    /// @param _flywheelBooster The address of the FlywheelBooster module contract.
    /// @param _owner The address of the contract owner.
    /// @param _authority The address of the Authority contract.
    constructor(
        ERC20 _rewardToken,
        IFlywheelRewards _flywheelRewards,
        IFlywheelBooster _flywheelBooster,
        address _owner,
        Authority _authority
    ) Auth(_owner, _authority) {
        // Set contract addresses.
        rewardToken = _rewardToken;
        flywheelRewards = _flywheelRewards;
        flywheelBooster = _flywheelBooster;

        // Set the applyBoosting variable to true if a booster contract is set.
        applyBoosting = address(_flywheelBooster) != address(0);
    }

    /*///////////////////////////////////////////////////////////////
                          BOOSTER CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Immutable indicating whether the contract has boosting enabled.
    bool public immutable applyBoosting;

    /// @notice The FlyWheelBooster contract address.
    IFlywheelBooster public immutable flywheelBooster;

    /*///////////////////////////////////////////////////////////////
                          REWARD CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice The FlyWheelRewards contract address.
    IFlywheelRewards public flywheelRewards;

    /// @notice Emitted when the booster module is changed.
    /// @param user The authorized user who triggered the change.
    /// @param oldFlywheelRewards The old FlywheelRewards contract address.
    /// @param newFlywheelRewards The new FlywheelRewards contract address.
    event FlywheelRewardsUpdated(
        address indexed user,
        IFlywheelRewards indexed oldFlywheelRewards,
        IFlywheelRewards indexed newFlywheelRewards
    );

    /// @notice Set a new FlywheelRewards contract.
    function setFlywheelRewards(IFlywheelRewards newFlywheelRewards) external requiresAuth {
        // Store the old contract address.
        IFlywheelRewards oldFlywheelRewards = flywheelRewards;

        // Update the FlywheelRewards contract address.
        flywheelRewards = newFlywheelRewards;

        // Emit the event.
        emit FlywheelRewardsUpdated(msg.sender, oldFlywheelRewards, newFlywheelRewards);
    }

    /*///////////////////////////////////////////////////////////////
                          MARKET CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Packed struct used to store a market's index and the timestamp of its last update.
    struct RewardsState {
        /// @notice The market's last updated index.
        /// @dev This value is scaled by 1e18.
        uint224 index;
        /// @notice The timestamp the index was last updated at.
        uint32 lastUpdatedTimestamp;
    }

    /// @notice The market index and last updated per market
    mapping(ERC20 => RewardsState) public marketState;

    /// @notice Emitted when a new market is added.
    /// @param user The authorized user who triggered the change.
    /// @param newMarket The new market address.
    event MarketAdded(address indexed user, ERC20 indexed newMarket);

    /// @notice Add a new ERC20 Market contract to distribute rewards to.
    /// @param market The address of the market to add.
    function addMarket(ERC20 market) external requiresAuth {
        // Ensure the market hasn't already been added.
        require(marketState[market].index == 0, "MARKET_ALREADY_ADDED");

        // Add the market to the marketState map.
        marketState[market] = RewardsState({index: 1e18, lastUpdatedTimestamp: uint32(block.timestamp)});

        // Emit the event.
        emit MarketAdded(msg.sender, market);
    }

    /*///////////////////////////////////////////////////////////////
                               REWARD LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice The accrued rewards per user, not including claimed or transfered rewards.
    mapping(address => uint256) public rewardsAccrued;

    /// @notice User indexes per market.
    mapping(ERC20 => mapping(address => uint224)) public userIndices;

    /// @notice Emitted after a Rewards Accrual.
    /// @param market The address of the market whose state was updated.
    /// @param user The address of the user whose accrued rewards.
    /// @param rewardsDelta The delta between the user's previous index and the current market index.
    /// @param rewardsIndex Current market index.
    event RewardsAccrued(ERC20 indexed market, address indexed user, uint256 rewardsDelta, uint256 rewardsIndex);

    /// @notice Accrue rewards for a single user on a market.
    /// @param market The address of the market to accrue rewards for.
    /// @param user The address of the user to accrue rewards for.
    /// @return Accumulated rewards.
    function accrue(ERC20 market, address user) public returns (uint256) {
        // Cache the global market state.
        RewardsState memory state = marketState[market];

        // If the market has not been added, return 0.
        if (state.index == 0) return 0;

        // Accrue market rewards.
        state = accrueMarket(market, state);

        // Calculate, store, and return the user's accrued rewards.
        return accrueUser(market, user, state);
    }

    /// @notice Accrue rewards for two users on a market.
    /// @param market The address of the market to accrue rewards for.
    /// @param user1 The address of the first user to accrue rewards for.
    /// @param user2 The address of the second user to accrue rewards for.
    /// @return Accumulated rewards for both users.
    function accrue(
        ERC20 market,
        address user1,
        address user2
    ) public returns (uint256, uint256) {
        // Cache the global market state.
        RewardsState memory state = marketState[market];

        // If the market has not been added, return 0 for both users.
        if (state.index == 0) return (0, 0);

        // Accrue market rewards.
        state = accrueMarket(market, state);

        // Calculate, store, and return the users' accrued rewards.
        return (accrueUser(market, user1, state), accrueUser(market, user2, state));
    }

    /// @notice Accumulate global rewards on a given market.
    /// @param market The address of the market to accumulate rewards for.
    /// @param state The state of the market at the time of the reward accumulation.
    /// @return newState The new market state.
    function accrueMarket(ERC20 market, RewardsState memory state) internal returns (RewardsState memory) {
        // Calculate the accrued rewards using the FlywheelRewards module.
        uint256 accrued = flywheelRewards.getAccruedRewards(market, state.lastUpdatedTimestamp);

        // If rewards have not accrued, return the current state.
        if (accrued == 0) return state;

        // If boosting is enabled, use it to calculate the Rewards Index denominator.
        // Otherwise just use the market's total supply.
        uint256 totalSupply = applyBoosting ? flywheelBooster.boostedTotalSupply(market) : market.totalSupply();

        // Accumulate token rewardds onto the index.
        RewardsState memory newState = RewardsState({
            index: state.index + (uint224((accrued * ONE) / totalSupply)),
            lastUpdatedTimestamp: uint32(block.timestamp)
        });

        // Update the market state.
        marketState[market] = newState;

        // Return the new state.
        return newState;
    }

    /// @notice Accumulate rewards on a specific market for a given user.
    /// @param market The address of the market to accumulate rewards for.
    /// @param user The address of the user to accumulate rewards for.
    /// @param state The state of the market at the time of the reward accumulation.
    /// @return Accumulated rewards for the user.
    function accrueUser(
        ERC20 market,
        address user,
        RewardsState memory state
    ) internal returns (uint256) {
        // Load indices.
        uint224 marketIndex = state.index;
        uint224 userIndex = userIndices[market][user];

        // Sync user index to market index.
        userIndices[market][user] = marketIndex;

        // If a user has yet to accrue rewards, grant them interest from the market beginning (if they have a balance).
        userIndex == 0 ? ONE : userIndex;

        // Calculate the delta between the market and user indices.
        uint224 indexDelta = marketIndex - userIndex;

        // If boosting is enabled, use it to calculate the reward balance multiplier.
        // Otherwise just use the user's token balance.
        uint256 userBalance = applyBoosting ? flywheelBooster.boostedBalanceOf(market, user) : market.balanceOf(user);

        // Accumulate rewards by multiplying user tokens by the delta and adding it to the accrued rewards.
        uint256 userDelta = (userBalance * indexDelta) / ONE;
        uint256 accrued = rewardsAccrued[user] + userDelta;

        // Store the new accrued reward amount.
        rewardsAccrued[user] = accrued;

        // Emit the event.
        emit RewardsAccrued(market, user, userDelta, marketIndex);

        // Return the new amount.
        return accrued;
    }

    /*///////////////////////////////////////////////////////////////
                               REWARD LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted after a user claims their rewards.
    /// @param user The address of the user claimed their rewards.
    /// @param amount The amount claimed.
    event RewardsClaimed(address indexed user, uint256 amount);

    /// @notice Claim
    function claimRewards(address user) external {
        // Retrieve the user's accrued rewards.
        uint256 accrued = rewardsAccrued[user];

        // If no rewards have been accrued, return.
        if (accrued == 0) return;

        // Reset the user's accrued rewards.
        delete rewardsAccrued[user];

        // Transfer the accrued rewards to the user.
        rewardToken.safeTransferFrom(address(flywheelRewards), user, accrued);

        // Emit the event.
        emit RewardsClaimed(user, accrued);
    }
}
