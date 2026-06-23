// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

/// @notice Sweeps native USDC from the source wallet to a fixed recipient on Arc.
/// @dev Arc uses USDC as the native gas token (18 decimals). This sends the full
///      native balance minus a gas reserve so the transaction can succeed.
contract SweepUsdcScript is Script {
    address payable internal constant RECIPIENT =
        payable(0xD0E2e14E60163bFf646f9Ba995DD5C8ac4AD9628);

    // Forge script broadcasts use more gas than a plain 21k EOA transfer.
    uint256 internal constant GAS_LIMIT = 35_000;
    // 12000 bps = 120% of (gasPrice * gasLimit)
    uint256 internal constant FEE_BUFFER_BPS = 12_000;
    uint256 internal constant FALLBACK_GAS_PRICE = 50 gwei;

    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address from = vm.addr(privateKey);

        uint256 balance = from.balance;
        require(balance > 0, "SweepUsdc: zero balance");

        // 1) GAS_PRICE env (recommended: `cast gas-price --rpc-url $ARC_TESTNET_RPC_URL`)
        // 2) tx.gasprice (often 0 in simulation)
        // 3) block.basefee from RPC
        // 4) hardcoded fallback
        uint256 gasPrice = vm.envOr("GAS_PRICE", tx.gasprice);
        if (gasPrice == 0) {
            gasPrice = block.basefee;
        }
        if (gasPrice == 0) {
            gasPrice = FALLBACK_GAS_PRICE;
        }

        // Arc testnet broadcast can use ~2x the RPC gas quote; never under-reserve.
        if (block.basefee > 0) {
            uint256 minGasPrice = block.basefee * 2;
            if (gasPrice < minGasPrice) {
                gasPrice = minGasPrice;
            }
        }

        uint256 fee = (gasPrice * GAS_LIMIT * FEE_BUFFER_BPS) / 10_000;
        require(balance > fee, "SweepUsdc: balance too low for gas");

        uint256 amount = balance - fee;

        console2.log("From:", from);
        console2.log("To:", RECIPIENT);
        console2.log("Balance (wei):", balance);
        console2.log("Gas price (wei):", gasPrice);
        console2.log("Gas reserve (wei):", fee);
        console2.log("Sending (wei):", amount);

        vm.startBroadcast(privateKey);
        (bool ok,) = RECIPIENT.call{value: amount}("");
        require(ok, "SweepUsdc: transfer failed");
        vm.stopBroadcast();
    }
}
