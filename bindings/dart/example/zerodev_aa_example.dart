// ZeroDev Omni SDK — Dart example.
//
// Run it with the native library on the search path:
//
//   cd bindings/dart && make run
//   # or: ZERODEV_SDK_ROOT=$(git rev-parse --show-toplevel) \
//   #       dart run example/zerodev_aa_example.dart
//
// With no ZERODEV_PROJECT_ID it derives and prints the smart-account address
// offline. Set ZERODEV_PROJECT_ID to a sponsoring project to also send a
// gasless self-call and wait for its receipt.
import 'dart:io';

import 'package:zerodev_aa/zerodev_aa.dart';

Future<void> main() async {
  final projectId = Platform.environment['ZERODEV_PROJECT_ID'] ?? 'test-project';
  final live = projectId != 'test-project';

  final ctx = Context.create(
    projectId,
    rpcUrl: Platform.environment['RPC_URL'] ?? '',
    bundlerUrl: Platform.environment['BUNDLER_URL'] ?? '',
    chainId: 11155111, // Sepolia
  );
  final signer = Signer.generate();
  final account = ctx.newAccount(signer);

  try {
    final address = await account.getAddressAsync();
    stdout.writeln('Smart account: ${address.toHex()}');

    if (!live) {
      stdout.writeln('Set ZERODEV_PROJECT_ID to send a gasless UserOperation.');
      return;
    }

    stdout.writeln('Sending a gasless self-call...');
    final hash = await account.sendUserOpAsync([Call(target: address)]);
    stdout.writeln('UserOp hash: ${hash.toHex()}');

    final receipt = await account.waitForUserOperationReceiptAsync(hash);
    stdout.writeln('Included, success: ${receipt.success}');
  } finally {
    account.dispose();
    signer.dispose();
    ctx.dispose();
  }
}
