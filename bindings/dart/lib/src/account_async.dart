part of 'sdk.dart';

/// Async variants of the blocking [Account] methods.
///
/// For an account backed by a native signer ([Signer.local], [Signer.generate],
/// [Signer.rpc]) and the built-in HTTP client, these run the blocking native
/// call on a background isolate so the calling isolate stays responsive — the
/// point of the Swift binding's async API, and what a Flutter UI wants.
///
/// An account backed by a Dart [SignerImpl] or a Dart [HttpTransport] cannot be
/// offloaded — those callbacks are bound to the isolate that created them — so
/// for such accounts the methods run synchronously on the current isolate.
extension AccountAsync on Account {
  /// [Account.getAddress], off the calling isolate when possible.
  Future<Address> getAddressAsync() async {
    if (_usesDartCallbacks) return getAddress();
    final path = NativeLibrary.instance.path;
    final addr = _handle.address;
    return Address(await Isolate.run(() => _isoGetAddress(path, addr)));
  }

  /// [Account.sendUserOp], off the calling isolate when possible.
  Future<Hash> sendUserOpAsync(List<Call> calls) async {
    if (_usesDartCallbacks) return sendUserOp(calls);
    final path = NativeLibrary.instance.path;
    final addr = _handle.address;
    final payload = _callsToPayload(calls);
    return Hash(await Isolate.run(() => _isoSendUserOp(path, addr, payload)));
  }

  /// [Account.buildUserOp], off the calling isolate when possible.
  Future<UserOp> buildUserOpAsync(List<Call> calls) async {
    if (_usesDartCallbacks) return buildUserOp(calls);
    final path = NativeLibrary.instance.path;
    final addr = _handle.address;
    final payload = _callsToPayload(calls);
    final opAddr = await Isolate.run(() => _isoBuildUserOp(path, addr, payload));
    return UserOp._(Pointer<aa_userop_t>.fromAddress(opAddr), this);
  }

  /// [Account.waitForUserOperationReceipt], off the calling isolate when
  /// possible. This is the call most worth offloading — it polls for up to
  /// [timeoutMs].
  Future<UserOperationReceipt> waitForUserOperationReceiptAsync(
    Hash useropHash, {
    int timeoutMs = 0,
    int pollIntervalMs = 0,
  }) async {
    if (_usesDartCallbacks) {
      return waitForUserOperationReceipt(useropHash,
          timeoutMs: timeoutMs, pollIntervalMs: pollIntervalMs);
    }
    final path = NativeLibrary.instance.path;
    final addr = _handle.address;
    final hash = useropHash.bytes;
    final json = await Isolate.run(
        () => _isoWaitReceipt(path, addr, hash, timeoutMs, pollIntervalMs));
    return UserOperationReceipt(json);
  }
}

/// A sendable representation of a [Call] list: (target, value, calldata) bytes.
List<(Uint8List, Uint8List, Uint8List)> _callsToPayload(List<Call> calls) => [
      for (final c in calls) (c.target.bytes, c.value, c.calldata),
    ];

Pointer<aa_call_t> _payloadToNative(
    Allocator arena, List<(Uint8List, Uint8List, Uint8List)> calls) {
  final arr = arena<aa_call_t>(calls.length);
  for (var i = 0; i < calls.length; i++) {
    final c = (arr + i).ref;
    final (target, value, calldata) = calls[i];
    for (var j = 0; j < 20; j++) {
      c.target[j] = target[j];
    }
    for (var j = 0; j < 32; j++) {
      c.value_be[j] = value[j];
    }
    c.calldata = _toNative(arena, calldata);
    c.calldata_len = calldata.length;
  }
  return arr;
}

// ---- Runs inside a background isolate (top-level, no captured `this`) ----

Uint8List _isoGetAddress(String path, int accAddr) {
  final b = NativeLibrary.open(path: path).bindings;
  return using((arena) {
    final out = arena<Uint8>(20);
    _checkFrom(b, b.aa_account_get_address(
        Pointer<aa_account_t>.fromAddress(accAddr), out));
    return Uint8List.fromList(out.asTypedList(20));
  });
}

Uint8List _isoSendUserOp(
    String path, int accAddr, List<(Uint8List, Uint8List, Uint8List)> calls) {
  final b = NativeLibrary.open(path: path).bindings;
  return using((arena) {
    final arr = _payloadToNative(arena, calls);
    final out = arena<Uint8>(32);
    _checkFrom(b, b.aa_send_userop(
        Pointer<aa_account_t>.fromAddress(accAddr), arr, calls.length, out));
    return Uint8List.fromList(out.asTypedList(32));
  });
}

int _isoBuildUserOp(
    String path, int accAddr, List<(Uint8List, Uint8List, Uint8List)> calls) {
  final b = NativeLibrary.open(path: path).bindings;
  return using((arena) {
    final arr = _payloadToNative(arena, calls);
    final out = arena<Pointer<aa_userop_t>>();
    _checkFrom(b, b.aa_userop_build(
        Pointer<aa_account_t>.fromAddress(accAddr), arr, calls.length, out));
    return out.value.address;
  });
}

String _isoWaitReceipt(String path, int accAddr, Uint8List useropHash,
    int timeoutMs, int pollIntervalMs) {
  final b = NativeLibrary.open(path: path).bindings;
  return using((arena) {
    final hash = _toNative(arena, useropHash);
    final jsonOut = arena<Pointer<Char>>();
    final lenOut = arena<Size>();
    _checkFrom(
        b,
        b.aa_wait_for_user_operation_receipt(
          Pointer<aa_account_t>.fromAddress(accAddr),
          hash,
          timeoutMs,
          pollIntervalMs,
          jsonOut,
          lenOut,
        ));
    final json = jsonOut.value.cast<Utf8>().toDartString(length: lenOut.value);
    b.aa_free(jsonOut.value.cast());
    return json;
  });
}

void _checkFrom(AaBindings b, aa_status status) {
  if (status == aa_status.AA_OK) return;
  final p = b.aa_get_last_error();
  final detail = p == nullptr ? '' : p.cast<Utf8>().toDartString();
  throw AaException(status.value, detail);
}
