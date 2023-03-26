# UMA-safe

UMA-safe is a set of smart contract that allows permissionless
creation of insurance pools for ERC4626 vaults/tokens. It allows
anyone to create a pool by giving the following parameters:

1. `protectedToken` - The ERC4626 vault token address.
2. `underwritingToken` - The token in which the insurance is being underwritten.
3. `payoutRatio` - The underwritingTokenPayoutAmount : protectedTokenAmount ratio. This is the ratio that the user is paid out if the vault gets hacked.
4. `expiration` - The timestamp until which the insurance is provided. After expiry the underwriters claim both the premium and their original deposits back in case of no hacks.
5. `premium` - The premium charged per protectedToken.

Anyone can register the hack by calling `registerHack` providing the minimum bonding amount
for USDC token. The liveness period for the same is 7 days. Anyone can dispute the hack
in case of falsified claims that can and will then be settled by the UMA protocol.

After it is settled, the callback will notify the contract of whether the vault was
really hacked or not. If it was hacked, all the insured users can claim by calling `claimInsured`.
They will be paid out according to their Insurer Receipt Token balance and the payout ratio.

The insurers can claim any unutilized deployed capital as well then by calling `claimInsurer`.
