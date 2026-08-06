part of 'sdk.dart';

/// A Kernel smart account.
///
/// Send UserOperations with [sendUserOp], or drive the pipeline step by step
/// with [buildUserOp]. The account keeps its [Context] and [Signer] alive, so
/// they are not collected while it is in use (audit F-09). [dispose] it when
/// done.
class Account implements Finalizable {
  Account._(this._ptr, this._context, this._signer) {
    _finalizer.attach(this, _AccountToken(_ptr), detach: this);
  }

  final Pointer<aa_account_t> _ptr;

  // Strong references so the context/signer outlive the account (F-09).
  final Context _context;
  final Signer _signer;
  bool _disposed = false;

  /// Whether this account is backed by a Dart [SignerImpl] or [HttpTransport],
  /// whose callbacks are bound to their creating isolate and so cannot be run
  /// from a background isolate (see [AccountAsync]).
  bool get _usesDartCallbacks =>
      _signer._bridge != null || _context._httpBridge != null;

  static final Finalizer<_AccountToken> _finalizer =
      Finalizer<_AccountToken>((t) => t.destroy());

  Pointer<aa_account_t> get _handle {
    if (_disposed) throw StateError('Account has been disposed');
    return _ptr;
  }

  /// The account's 20-byte address (counterfactual until first deployed).
  Address getAddress() {
    return using((arena) {
      final out = arena<Uint8>(20);
      checkStatus(_bindings.aa_account_get_address(_handle, out));
      return Address(Uint8List.fromList(out.asTypedList(20)));
    });
  }

  /// The account address as `0x`-prefixed hex.
  String getAddressHex() => getAddress().toHex();

  /// Build a UserOperation from [calls] without sending it, for step-by-step
  /// control ([UserOp.hash], [UserOp.sign], [UserOp.toJson], ...).
  UserOp buildUserOp(List<Call> calls) {
    return using((arena) {
      final arr = _marshalCalls(arena, calls);
      final out = arena<Pointer<aa_userop_t>>();
      checkStatus(_bindings.aa_userop_build(_handle, arr, calls.length, out));
      return UserOp._(out.value, this);
    });
  }

  /// Build, sign, and submit a UserOperation for [calls], returning its hash.
  Hash sendUserOp(List<Call> calls) {
    return using((arena) {
      final arr = _marshalCalls(arena, calls);
      final out = arena<Uint8>(32);
      checkStatus(_bindings.aa_send_userop(_handle, arr, calls.length, out));
      return Hash(Uint8List.fromList(out.asTypedList(32)));
    });
  }

  /// Poll for [useropHash] to be included on-chain and return its receipt.
  ///
  /// [timeoutMs] caps the wait (0 = 60s default); [pollIntervalMs] is the poll
  /// period (0 = 2s default).
  UserOperationReceipt waitForUserOperationReceipt(
    Hash useropHash, {
    int timeoutMs = 0,
    int pollIntervalMs = 0,
  }) {
    return using((arena) {
      final hash = _toNative(arena, useropHash.bytes);
      final jsonOut = arena<Pointer<Char>>();
      final lenOut = arena<Size>();
      checkStatus(_bindings.aa_wait_for_user_operation_receipt(
        _handle,
        hash,
        timeoutMs,
        pollIntervalMs,
        jsonOut,
        lenOut,
      ));
      final json = jsonOut.value.cast<Utf8>().toDartString(length: lenOut.value);
      _bindings.aa_free(jsonOut.value.cast());
      return UserOperationReceipt(json);
    });
  }

  /// Release the account. Does not dispose its context or signer.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _finalizer.detach(this);
    _bindings.aa_account_destroy(_ptr);
  }

  /// Alias for [dispose].
  void close() => dispose();

  Pointer<aa_call_t> _marshalCalls(Allocator arena, List<Call> calls) {
    if (calls.isEmpty) {
      throw AaException(AaErrorCode.noCalls.code, 'a UserOperation needs at least one call');
    }
    final arr = arena<aa_call_t>(calls.length);
    for (var i = 0; i < calls.length; i++) {
      final c = (arr + i).ref;
      final call = calls[i];
      for (var j = 0; j < 20; j++) {
        c.target[j] = call.target.bytes[j];
      }
      for (var j = 0; j < 32; j++) {
        c.value_be[j] = call.value[j];
      }
      c.calldata = _toNative(arena, call.calldata);
      c.calldata_len = call.calldata.length;
    }
    return arr;
  }
}

/// GC-time cleanup for an [Account] that was never disposed.
class _AccountToken {
  _AccountToken(this.ptr);

  final Pointer<aa_account_t> ptr;

  void destroy() => _bindings.aa_account_destroy(ptr);
}
