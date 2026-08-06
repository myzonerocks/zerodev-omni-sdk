// ZeroDev Gasless Transfer via EIP-7702 — Dart Example.
//
// Sends a sponsored (gasless) UserOperation from an EIP-7702-delegated EOA on
// Sepolia. The account address IS the signer's EOA — on the first UserOperation
// the SDK signs an authorization tuple (chainId, kernelImpl, nonce) and attaches
// it via the eip7702Auth field; subsequent ops skip the auth once the delegation
// is installed on-chain.
//
// Requirements:
//   ZERODEV_PROJECT_ID  — your ZeroDev project ID
//   PRIVATE_KEY         — (optional) 32-byte hex private key; generated if omitted
import 'dart:io';

import 'package:zerodev_aa/zerodev_aa.dart';

Future<void> main() async {
  print('=======================================================');
  print('  ZeroDev Gasless Transfer (EIP-7702) — Dart Example');
  print('=======================================================\n');

  // Step 1: read environment variables.
  final projectId = Platform.environment['ZERODEV_PROJECT_ID'] ?? '';
  if (projectId.isEmpty) {
    stderr.writeln('Error: ZERODEV_PROJECT_ID environment variable is required.');
    stderr.writeln('Usage:');
    stderr.writeln('  export ZERODEV_PROJECT_ID=<your-project-id>');
    stderr.writeln('  export PRIVATE_KEY=<32-byte-hex-private-key>  # optional');
    stderr.writeln('  dart run main.dart');
    exit(1);
  }
  final pkHex = Platform.environment['PRIVATE_KEY'] ?? '';
  print('[1/6] Configuration loaded (project: $projectId, chain: Sepolia 11155111)');

  // Step 2: create the context with ZeroDev gas + paymaster on Sepolia.
  final ctx = Context.create(projectId, chainId: 11155111);
  print('[2/6] Context created (gas: ZeroDev, paymaster: ZeroDev)');

  // Step 3: create the signer — a fresh random EOA by default.
  final signer = pkHex.isNotEmpty ? Signer.local(hexDecode(pkHex)) : Signer.generate();
  print(pkHex.isNotEmpty
      ? '[3/6] Signer created (from PRIVATE_KEY)'
      : '[3/6] Signer created (fresh random EOA — no prior delegation)');

  // Step 4: create the EIP-7702 delegated account (its address IS the EOA).
  final account = ctx.newAccount7702(signer);
  final address = account.getAddress();
  print('[4/6] EIP-7702 account ready: ${address.toHex()}');
  print('       (EOA == smart-account address)');

  try {
    // Step 5: send a gasless zero-value self-call.
    print('[5/6] Sending gasless self-call...');
    final hash = await account.sendUserOpAsync([Call(target: address)]);
    print('       UserOp hash: ${hash.toHex()}');

    // Step 6: wait for the receipt.
    final receipt = await account.waitForUserOperationReceiptAsync(hash);
    print('[6/6] Included — success: ${receipt.success}');
  } finally {
    account.dispose();
    signer.dispose();
    ctx.dispose();
  }
}
