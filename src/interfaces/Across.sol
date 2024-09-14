// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;
pragma experimental ABIEncoderV2;

interface IHubPool {
    function addLiquidity(address l1Token, uint256 l1TokenAmount) external payable;
    function removeLiquidity(address l1Token, uint256 lpTokenAmount, bool sendEth) external;
    function pooledTokens(address l1Token) external view returns (address lpToken, bool isEnabled, uint32 lastLpFeeUpdate, int256 utilizedReserves, uint256 liquidReserves, uint256 undistributedLpFees);
    function exchangeRateCurrent(address l1Token) external returns (uint256);
}

interface IStaking {
    function stake(address stakedToken, uint256 amount) external;
    function unstake(address stakedToken, uint256 amount) external;
    function withdrawReward(address stakedToken) external;
    function getUserStake(address stakedToken, address account) external view returns (uint256 cumulativeBalance, uint256 averageDepositTime, uint256 rewardsAccumulatedPerToken, uint256 rewardsOutstanding);
    function getOutstandingRewards(address stakedToken, address account) external view returns (uint256);
    function stakingTokens(address stakedToken) external view returns (bool enabled, uint256 baseEmissionRate, uint256 maxMultiplier, uint256 secondsToMaxMultiplier, uint256 cumulativeStaked, uint256 rewardPerTokenStored, uint256 lastUpdateTime);
}