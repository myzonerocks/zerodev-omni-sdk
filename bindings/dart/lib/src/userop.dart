part of 'sdk.dart';

/// A UserOperation under step-by-step construction.
///
/// Returned by [Account.buildUserOp] for callers driving the pipeline
/// themselves — [hash] it, [sign] it, serialize with [toJson], and fold in
/// gas/paymaster results with [applyGasJson] / [applyPaymasterJson]. Most
/// callers should use [Account.sendUserOp] instead. Keeps its account alive;
/// [dispose] it when done.
class UserOp implements Finalizable {
  UserOp._(this._ptr, this._account) {
    _finalizer.attach(this, _UserOpToken(_ptr), detach: this);
  }

  final Pointer<aa_userop_t> _ptr;

  // Strong reference so the account outlives the userop.
  final Account _account;
  bool _disposed = false;

  static final Finalizer<_UserOpToken> _finalizer =
      Finalizer<_UserOpToken>((t) => t.destroy());

  Pointer<aa_userop_t> get _handle {
    if (_disposed) throw StateError('UserOp has been disposed');
    return _ptr;
  }

  /// The 32-byte hash the signer signs.
  Hash hash() {
    return using((arena) {
      final out = arena<Uint8>(32);
      checkStatus(_bindings.aa_userop_hash(_handle, _account._handle, out));
      return Hash(Uint8List.fromList(out.asTypedList(32)));
    });
  }

  /// Sign the operation in place with the account's signer.
  void sign() => checkStatus(_bindings.aa_userop_sign(_handle, _account._handle));

  /// Serialize the operation to its JSON-RPC representation.
  String toJson() {
    return using((arena) {
      final jsonOut = arena<Pointer<Char>>();
      final lenOut = arena<Size>();
      checkStatus(_bindings.aa_userop_to_json(_handle, jsonOut, lenOut));
      final json = jsonOut.value.cast<Utf8>().toDartString(length: lenOut.value);
      _bindings.aa_free(jsonOut.value.cast());
      return json;
    });
  }

  /// Apply an `eth_estimateUserOperationGas` result ([gasJson]) to the op.
  void applyGasJson(String gasJson) {
    using((arena) {
      final s = gasJson.toNativeUtf8(allocator: arena);
      checkStatus(_bindings.aa_userop_apply_gas_json(_handle, s.cast(), s.length));
    });
  }

  /// Apply a paymaster sponsorship result ([pmJson]) to the op.
  void applyPaymasterJson(String pmJson) {
    using((arena) {
      final s = pmJson.toNativeUtf8(allocator: arena);
      checkStatus(_bindings.aa_userop_apply_paymaster_json(_handle, s.cast(), s.length));
    });
  }

  /// Release the operation. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _finalizer.detach(this);
    _bindings.aa_userop_destroy(_ptr);
  }

  /// Alias for [dispose].
  void close() => dispose();
}

/// GC-time cleanup for a [UserOp] that was never disposed.
class _UserOpToken {
  _UserOpToken(this.ptr);

  final Pointer<aa_userop_t> ptr;

  void destroy() => _bindings.aa_userop_destroy(ptr);
}
