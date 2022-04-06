// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

abstract contract CERC20 {
   
    function mint(uint256 underlyingAmount) external virtual returns (uint256);

   
    function borrow(uint256 underlyingAmount) external virtual returns (uint256);

   
    function repayBorrow(uint256 underlyingAmount) external virtual returns (uint256);

   
    function balanceOfUnderlying(address user) external view virtual returns (uint256);


    function exchangeRateStored() external view virtual returns (uint256);


    function redeemUnderlying(uint256 underlyingAmount) external virtual returns (uint256);


    function borrowBalanceCurrent(address user) external virtual returns (uint256);

    function repayBorrowBehalf(address user, uint256 underlyingAmount) external virtual returns (uint256);
}
