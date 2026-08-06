import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'ffi/aa_bindings.g.dart';
import 'native_loader.dart';

/// The status codes the native SDK returns, mirroring `aa_status` in aa.h.
enum AaErrorCode {
  ok(0, 'OK'),
  nullOutPtr(1, 'NullOutPtr'),
  invalidUrl(2, 'InvalidUrl'),
  outOfMemory(3, 'OutOfMemory'),
  invalidPrivateKey(4, 'InvalidPrivateKey'),
  invalidKernelVersion(5, 'InvalidKernelVersion'),
  nullContext(6, 'NullContext'),
  nullAccount(7, 'NullAccount'),
  nullUserOp(8, 'NullUserOp'),
  getAddressFailed(9, 'GetAddressFailed'),
  buildUserOpFailed(10, 'BuildUserOpFailed'),
  hashUserOpFailed(11, 'HashUserOpFailed'),
  signUserOpFailed(12, 'SignUserOpFailed'),
  sendUserOpFailed(13, 'SendUserOpFailed'),
  estimateGasFailed(14, 'EstimateGasFailed'),
  paymasterFailed(15, 'PaymasterFailed'),
  noCalls(16, 'NoCalls'),
  invalidHex(17, 'InvalidHex'),
  applyJsonFailed(18, 'ApplyJsonFailed'),
  serializeFailed(19, 'SerializeFailed'),
  noGasMiddleware(20, 'NoGasMiddleware'),
  noPaymasterMiddleware(21, 'NoPaymasterMiddleware'),
  receiptTimeout(22, 'ReceiptTimeout'),
  receiptFailed(23, 'ReceiptFailed'),
  invalidSigner(24, 'InvalidSigner');

  const AaErrorCode(this.code, this.label);

  /// The numeric `aa_status` value.
  final int code;

  /// The status name as written in the C enum (e.g. `SendUserOpFailed`).
  final String label;

  /// The code matching [value], or null for an unrecognized status.
  static AaErrorCode? fromValue(int value) {
    for (final c in AaErrorCode.values) {
      if (c.code == value) return c;
    }
    return null;
  }
}

/// Raised when a native call returns a non-`OK` status.
///
/// [code] is the raw `aa_status`, [name] its enum name, and [detail] the
/// message from `aa_get_last_error` (empty for status codes that carry no
/// message).
class AaException implements Exception {
  AaException(this.code, [this.detail = '']);

  /// The numeric `aa_status` value.
  final int code;

  /// The last-error message, or empty when the status carries none.
  final String detail;

  /// The enum name for [code], or `Unknown(<code>)` if unrecognized.
  String get name => AaErrorCode.fromValue(code)?.label ?? 'Unknown($code)';

  /// The typed error code, or null for an unrecognized status.
  AaErrorCode? get errorCode => AaErrorCode.fromValue(code);

  @override
  String toString() => detail.isEmpty
      ? '$name (code $code)'
      : '$name (code $code): $detail';
}

/// The message from the SDK's thread-local last-error slot, or empty.
///
/// The returned pointer is owned by the SDK and must not be freed.
String lastErrorMessage() {
  final ptr = NativeLibrary.instance.bindings.aa_get_last_error();
  if (ptr == nullptr) return '';
  return ptr.cast<Utf8>().toDartString();
}

/// Throw [AaException] with the last-error detail when [status] is not `OK`.
void checkStatus(aa_status status) {
  if (status == aa_status.AA_OK) return;
  throw AaException(status.value, lastErrorMessage());
}
