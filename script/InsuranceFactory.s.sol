pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {InsuranceFactory} from "src/InsuranceFactory.sol";
import {OptimisticOracleV3Interface} from "src/OptimisticOracleV3.sol";

address constant POLYGON_OPTIMISTIC_ORACLE = 0x5953f2538F613E05bAED8A5AeFa8e6622467AD3D;

contract InsuranceFactoryScript is Script {
    function run() external {
        new InsuranceFactory(
            OptimisticOracleV3Interface(POLYGON_OPTIMISTIC_ORACLE)
        );
    }
}
