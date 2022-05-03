pragma solidity 0.6.12;

interface IAntFarm {

    function initFarm(
        bytes calldata data
    ) external;
    function farmTemplate() external view returns (uint256);

}