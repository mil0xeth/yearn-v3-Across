// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;
import "forge-std/console.sol";
import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IHubPool, IStaking} from "./interfaces/Across.sol";
import {UniswapV3Swapper} from "@periphery/swappers/UniswapV3Swapper.sol";

contract AcrossLender is BaseStrategy, UniswapV3Swapper {
    receive() external payable {}
    using SafeERC20 for ERC20;
    address internal constant HUBPOOL = 0xc186fA914353c44b2E33eBE05f21846F1048bEda;
    address internal constant STAKING = 0x9040e41eF5E8b281535a96D9a48aCb8cfaBD9a48;
    address internal immutable lpToken;

    address internal constant rewardToken = 0x44108f0223A3C3028F5Fe7AEC7f9bb2E66beF82F;

    address internal constant weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // Represents if we should claim rewards. Default to true.
    bool public claimRewards = true;

    uint256 internal constant WAD = 1e18;

    constructor(address _asset, uint24 _feeBaseToAsset, string memory _name) BaseStrategy(_asset, _name) {
        (address _lpToken, bool isEnabled, , , , ) = IHubPool(HUBPOOL).pooledTokens(address(asset));
        lpToken = _lpToken;
        require(isEnabled, "!enabled");
    
        asset.forceApprove(HUBPOOL, type(uint256).max);
        ERC20(lpToken).forceApprove(STAKING, type(uint256).max);

        // Set the min amount for the swapper to sell
        _setUniFees(rewardToken, base, 10000);
        _setUniFees(base, address(asset), _feeBaseToAsset);
        minAmountToSell = 50e18; // 100 ACX = 25 USD
    }

    function _deployFunds(uint256 _amount) internal override {
        IHubPool(HUBPOOL).addLiquidity(address(asset), _amount);
        IStaking(STAKING).stake(lpToken, balanceOfLp());
    }

    function _freeFunds(uint256 _amount) internal override {
        uint256 lpAmount = _assetToLp(_amount);
        lpAmount = _min(lpAmount, balanceOfStake());
        require(lpAmount > 0, "withdraw amount too small");
        IStaking(STAKING).unstake(lpToken, lpAmount);
        lpAmount = _min(lpAmount, balanceOfLp());
        IHubPool(HUBPOOL).removeLiquidity(address(asset), lpAmount, false);
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        if (claimRewards) {
            IStaking(STAKING).withdrawReward(lpToken);
            console.log("rewards before: ", balanceOfRewards());
            _swapFrom(rewardToken, address(asset), balanceOfRewards(), 0); // minAmountOut = 0 since we only sell rewards
            console.log("rewards after: ", balanceOfRewards());
        }

        uint256 balance = balanceOfAsset();
        if (balance > 0) {
            _deployFunds(balance);
        }

        _totalAssets = balanceOfAsset() + _lpToAsset(balanceOfStake());
    }

    function availableDepositLimit(address /*_owner*/) public view override returns (uint256) {
        (, bool isEnabled, , , , ) = IHubPool(HUBPOOL).pooledTokens(address(asset));
        if (!isEnabled) return 0;
        return type(uint256).max;
    }

    function availableWithdrawLimit(address /*_owner*/) public view override returns (uint256) {
        (, , , , uint256 liquidReserves, ) = IHubPool(HUBPOOL).pooledTokens(address(asset));
        return balanceOfAsset() + liquidReserves;
    }

    function balanceOfAsset() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function balanceOfLp() public view returns (uint256) {
        return ERC20(lpToken).balanceOf(address(this));
    }

    function balanceOfStake() public view returns (uint256 _amount) {
        (_amount, , , ) = IStaking(STAKING).getUserStake(lpToken, address(this));
    }

    function balanceOfRewards() public view returns (uint256) {
        return ERC20(rewardToken).balanceOf(address(this));
    }

    function claimableRewards() public view returns (uint256) {
        return IStaking(STAKING).getOutstandingRewards(lpToken, address(this));
    }

    function _assetToLp(uint256 _assetAmount) internal view returns (uint256) {
        return _assetAmount * WAD / _exchangeRate();
    }

    function _lpToAsset(uint256 _lpAmount) internal view returns (uint256) {
        return _lpAmount * _exchangeRate() / WAD;
    }

    function _exchangeRate() internal view returns (uint256) {
        (, , , int256 utilizedReserves, uint256 liquidReserves, uint256 undistributedLpFees) = IHubPool(HUBPOOL).pooledTokens(address(asset));
        uint256 lpTokenTotalSupply = ERC20(lpToken).totalSupply();
        if (lpTokenTotalSupply == 0) return 1e18; // initial rate is 1:1 between LP tokens and collateral.

        // ExchangeRate := (liquidReserves + utilizedReserves - undistributedLpFees) / lpTokenSupply
        // Both utilizedReserves and undistributedLpFees contain assigned LP fees. UndistributedLpFees is gradually
        // decreased over the smear duration using _updateAccumulatedLpFees. This means that the exchange rate will
        // gradually increase over time as undistributedLpFees goes to zero.
        // utilizedReserves can be negative. If this is the case, then liquidReserves is offset by an equal
        // and opposite size. LiquidReserves + utilizedReserves will always be larger than undistributedLpFees so this
        // int will always be positive so there is no risk in underflow in type casting in the return line.
        int256 numerator = int256(liquidReserves) + utilizedReserves - int256(undistributedLpFees);
        return (uint256(numerator) * 1e18) / lpTokenTotalSupply;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    //////// EXTERNAL

    /**
     * @notice Set fees for UniswapV3 to sell rewardToken
     * @param _rewardToBase fee reward to base (weth/asset)
     * @param _baseToAsset fee base (weth/asset) to asset
     */
    function setUniFees(uint24 _rewardToBase, uint24 _baseToAsset) external onlyManagement {
        _setUniFees(rewardToken, base, _rewardToBase);
        _setUniFees(base, address(asset), _baseToAsset);
    }

    /**
     * @notice Set the minimum amount of rewardToken to sell
     * @param _minAmountToSell minimum amount to sell in wei
     */
    function setMinAmountToSell(uint256 _minAmountToSell) external onlyManagement {
        minAmountToSell = _minAmountToSell;
    }

    /**
     * @notice Swap the base token between `asset` and `weth`.
     * @dev This can be used for management to change which pool
     * to trade reward tokens.
     */
    function swapBase() external onlyManagement {
        base = base == address(asset) ? weth : address(asset);
    }

    /**
     * @notice Set the `claimRewards` bool.
     * @dev For management to set if the strategy should claim rewards during reports.
     * Can be turned off due to rewards being turned off or cause of an issue
     * in either the strategy or compound contracts.
     *
     * @param _claimRewards Bool representing if rewards should be claimed.
     */
    function setClaimRewards(bool _claimRewards) external onlyManagement {
        claimRewards = _claimRewards;
    }

    function _emergencyWithdraw(uint256 _amount) internal override {
        _freeFunds(_amount);
    }
}
