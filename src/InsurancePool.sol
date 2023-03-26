pragma solidity ^0.8.19;

import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {LibString} from "solady/utils/LibString.sol";

import {OptimisticOracleV3Interface, OptimisticOracleV3CallbackRecipientInterface} from "./OptimisticOracleV3.sol";
import {Mintable} from "./Mintable.sol";

address constant TOKEN_USDC = address(0x0);

using SafeTransferLib for ERC20;

contract InsurancePool is
    ReentrancyGuard,
    OptimisticOracleV3CallbackRecipientInterface
{
    error ActiveHackAssertion();
    error ActiveDispute();
    error OnlyOptimisticOracle();
    error InvalidAssertionId();
    error Hacked();
    error NotExpired();

    ERC4626 public immutable protectedToken;

    ERC20 public immutable underwritingToken;
    Mintable public immutable insuredReceiptToken;
    Mintable public immutable insurerReceiptToken;

    OptimisticOracleV3Interface public immutable optimisticOracle;

    uint public immutable payoutRatio;
    uint public immutable expiration;
    uint public immutable premium;

    uint8 public immutable protectedTokenDecimals;
    uint8 public immutable underwritingTokenDecimals;

    uint constant precision = 1e18;
    uint64 public constant disputeWindow = 7 days;

    ERC20 public constant bondToken = ERC20(TOKEN_USDC);
    bytes32 public constant OOV_domainId = keccak256("uma-safe");

    uint totalUnderwritingCapacity;
    uint totalPremiumCollected;
    uint totalUnderwritingCommitted;

    address hackRegistrant;
    bytes32 activeHackAssertionId;
    address disputeRegistrant;
    bytes32 disputeHackAssertionId;
    bool hasBeenHacked;

    constructor(
        ERC4626 _protectedToken,
        ERC20 _underwritingToken,
        uint _payoutRatio,
        uint _expiration,
        uint _premium,
        OptimisticOracleV3Interface _optimisticOracle
    ) {
        protectedToken = _protectedToken;
        underwritingToken = _underwritingToken;
        payoutRatio = _payoutRatio;
        expiration = _expiration;
        premium = _premium;

        protectedTokenDecimals = _protectedToken.decimals();
        underwritingTokenDecimals = _underwritingToken.decimals();

        insurerReceiptToken = new Mintable(
            string(
                abi.encodePacked(
                    "Insurer Receipt Token - ",
                    protectedToken.name()
                )
            ),
            string(abi.encodePacked("IRT-", protectedToken.symbol())),
            underwritingTokenDecimals
        );
        insuredReceiptToken = new Mintable(
            "Insured Receipt Token",
            string(abi.encodePacked("IDT-", protectedToken.symbol())),
            protectedTokenDecimals
        );

        optimisticOracle = _optimisticOracle;
    }

    function provideInsurance(
        uint _amount
    ) external nonReentrant onlyWhenNotHackedOrActiveAssertion {
        totalUnderwritingCapacity += _amount;

        underwritingToken.safeTransferFrom(msg.sender, address(this), _amount);
        insurerReceiptToken.mint(msg.sender, _amount);
    }

    function buyInsurance(
        uint _amountProtectedToken
    ) external nonReentrant onlyWhenNotHackedOrActiveAssertion {
        uint premiumToPay = _premiumFor(_amountProtectedToken);
        uint payout = _payoutFor(_amountProtectedToken);

        totalPremiumCollected += premiumToPay;
        totalUnderwritingCommitted += payout;

        underwritingToken.safeTransferFrom(
            msg.sender,
            address(this),
            premiumToPay
        );
        insuredReceiptToken.mint(msg.sender, _amountProtectedToken);
    }

    function registerHack() external noActiveHackAssertion nonReentrant {
        uint minBondAmount = optimisticOracle.getMinimumBond(
            address(bondToken)
        );
        bondToken.safeTransferFrom(msg.sender, address(this), minBondAmount);
        bondToken.safeApprove(address(optimisticOracle), minBondAmount);

        bytes32 assertionId = optimisticOracle.assertTruth(
            abi.encodePacked(
                "Was vault ",
                protectedToken.name(),
                "(",
                LibString.toHexStringChecksumed(address(protectedToken)),
                ") hacked?"
            ),
            msg.sender,
            address(this),
            address(0),
            disputeWindow,
            bondToken,
            minBondAmount,
            optimisticOracle.defaultIdentifier(),
            OOV_domainId
        );

        activeHackAssertionId = assertionId;
        hackRegistrant = msg.sender;
    }

    /// @dev nothing to do
    function assertionDisputedCallback(bytes32 assertionId) external {}

    function assertionResolvedCallback(
        bytes32 _assertionId,
        bool _truth
    ) external onlyOptimisticOracle {
        if (_assertionId != activeHackAssertionId) revert InvalidAssertionId();
        if (_truth) {
            hasBeenHacked = true;
        }
    }

    function claimInsured() external onlyWhenHacked nonReentrant {
        uint amountProtected = insuredReceiptToken.balanceOf(msg.sender);
        insuredReceiptToken.burn(msg.sender, amountProtected);
        uint amountToPay = (amountProtected * payoutRatio) / (10 ** precision);
        underwritingToken.safeTransfer(msg.sender, amountToPay);
    }

    function claimInsurer() external nonReentrant {
        if (hasBeenHacked) {
            uint remainder = totalUnderwritingCapacity -
                totalUnderwritingCommitted;
            uint remainderShare = (remainder *
                insurerReceiptToken.balanceOf(msg.sender)) /
                insurerReceiptToken.totalSupply();
            insurerReceiptToken.burn(msg.sender, remainderShare);
            underwritingToken.safeTransfer(msg.sender, remainderShare);
        } else if (block.timestamp > expiration) {} else {
            revert NotExpired();
        }
    }

    function _premiumFor(
        uint _amountProtectedToken
    ) internal view returns (uint) {
        return (_amountProtectedToken * premium) / (10 ** precision);
    }

    function _payoutFor(
        uint _amountProtectedToken
    ) internal view returns (uint) {
        return (_amountProtectedToken * payoutRatio) / (10 ** precision);
    }

    modifier noActiveHackAssertion() {
        if (activeHackAssertionId != bytes32(0) || hackRegistrant != address(0))
            revert ActiveHackAssertion();
        _;
    }

    modifier noActiveDispute() {
        if (
            disputeHackAssertionId != bytes32(0) ||
            disputeRegistrant != address(0)
        ) revert ActiveDispute();
        _;
    }

    modifier hasActiveHackAssertion() {
        if (activeHackAssertionId == bytes32(0) || hackRegistrant == address(0))
            revert ActiveHackAssertion();
        _;
    }

    modifier onlyOptimisticOracle() {
        if (msg.sender != address(optimisticOracle))
            revert OnlyOptimisticOracle();
        _;
    }

    modifier onlyWhenNotHackedOrActiveAssertion() {
        if (activeHackAssertionId != bytes32(0) || hackRegistrant != address(0))
            revert ActiveHackAssertion();

        if (hasBeenHacked) revert Hacked();
        _;
    }

    modifier onlyWhenHacked() {
        if (!hasBeenHacked) revert Hacked();
        _;
    }
}
