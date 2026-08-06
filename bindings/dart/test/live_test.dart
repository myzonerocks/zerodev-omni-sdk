@Tags(['live'])
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:zerodev_aa/zerodev_aa.dart';

/// End-to-end tests against ZeroDev Sepolia (chain 11155111). Set
/// `ZERODEV_PROJECT_ID` to a sponsoring project and run `dart test --tags live`.
/// They send a gasless zero-value self-call and wait for its receipt — the same
/// flow the go/rust/python/swift live tests exercise.
void main() {
  final projectId = Platform.environment['ZERODEV_PROJECT_ID'];
  final skip = projectId == null || projectId.isEmpty
      ? 'set ZERODEV_PROJECT_ID to run the live tests'
      : false;

  test('gasless self-call (local signer, Kernel v3.3)', () async {
    final ctx = Context.create(projectId!, chainId: 11155111);
    final signer = Signer.generate();
    final account = ctx.newAccount(signer);
    try {
      final address = account.getAddress();
      final hash = await account.sendUserOpAsync([Call(target: address)]);
      final receipt = await account.waitForUserOperationReceiptAsync(hash);
      expect(receipt.success, isTrue, reason: receipt.json);
    } finally {
      account.dispose();
      signer.dispose();
      ctx.dispose();
    }
  }, skip: skip);

  test('gasless self-call (EIP-7702 delegation)', () async {
    final ctx = Context.create(projectId!, chainId: 11155111);
    final signer = Signer.generate();
    final account = ctx.newAccount7702(signer);
    try {
      final address = account.getAddress();
      final hash = await account.sendUserOpAsync([Call(target: address)]);
      final receipt = await account.waitForUserOperationReceiptAsync(hash);
      expect(receipt.success, isTrue, reason: receipt.json);
    } finally {
      account.dispose();
      signer.dispose();
      ctx.dispose();
    }
  }, skip: skip);

  test('gasless self-call through the Dart HttpClient transport', () async {
    // The whole flow runs on a background isolate — the way a Flutter app
    // would drive it — routing HTTP through the Dart transport rather than the
    // core's built-in client.
    final id = projectId!;
    final json = await Isolate.run(() async {
      final ctx = Context.create(id, chainId: 11155111);
      await ctx.useHttpClientTransport();
      final signer = Signer.generate();
      final account = ctx.newAccount(signer);
      try {
        final hash = account.sendUserOp([Call(target: account.getAddress())]);
        return account.waitForUserOperationReceipt(hash).json;
      } finally {
        account.dispose();
        signer.dispose();
        ctx.dispose();
      }
    });
    expect(UserOperationReceipt(json).success, isTrue, reason: json);
  }, skip: skip);
}
