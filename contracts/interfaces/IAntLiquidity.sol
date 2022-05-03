pragma solidity 0.6.12;

interface IAntLiquidity {
    function initLauncher(
        bytes calldata data
    ) external;

    function getMarkets() external view returns(address[] memory);
    function liquidityTemplate() external view returns (uint256);
}
