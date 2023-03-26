pragma solidity ^0.8.19;

import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {InsurancePool} from "./InsurancePool.sol";
import {OptimisticOracleV3Interface} from "./OptimisticOracleV3.sol";

contract InsuranceFactory {
    OptimisticOracleV3Interface public immutable optimisticOracle;

    constructor(OptimisticOracleV3Interface _optimisticOracle) {
        optimisticOracle = _optimisticOracle;
    }

    function createInsurancePool(
        ERC4626 _protectedToken,
        ERC20 _underwritingToken,
        uint _payoutRatio,
        uint _expiration,
        uint _premium
    ) external {
        new InsurancePool(
            _protectedToken,
            _underwritingToken,
            _payoutRatio,
            _expiration,
            _premium,
            optimisticOracle
        );
    }
}
