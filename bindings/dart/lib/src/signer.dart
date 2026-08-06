part of 'sdk.dart';

/// A signer: the key that owns a smart account.
///
/// Create one with [Signer.local], [Signer.generate], [Signer.rpc], or
/// [Signer.custom], pass it to [Context.newAccount] / [Context.newAccount7702],
/// and [dispose] it when done (or wrap usage so it is always disposed). A
/// disposed signer must not be used again.
class Signer implements Finalizable {
  Signer._(this._ptr, this._bridge) {
    _finalizer.attach(this, _SignerToken(_ptr, _bridge), detach: this);
  }

  /// A local signer from a 32-byte [privateKey].
  factory Signer.local(Uint8List privateKey) {
    if (privateKey.length != 32) {
      throw ArgumentError.value(
          privateKey.length, 'privateKey', 'private key must be 32 bytes');
    }
    return using((arena) {
      final key = _toNative(arena, privateKey);
      final out = arena<Pointer<aa_signer_t>>();
      checkStatus(_bindings.aa_signer_local(key, out));
      return Signer._(out.value, null);
    });
  }

  /// A local signer with a freshly generated random private key.
  factory Signer.generate() {
    return using((arena) {
      final out = arena<Pointer<aa_signer_t>>();
      checkStatus(_bindings.aa_signer_generate(out));
      return Signer._(out.value, null);
    });
  }

  /// A JSON-RPC signer (Privy, custodial wallets) that signs via [rpcUrl] for
  /// the given 20-byte [address].
  factory Signer.rpc(String rpcUrl, Uint8List address) {
    if (address.length != 20) {
      throw ArgumentError.value(address.length, 'address', 'address must be 20 bytes');
    }
    return using((arena) {
      final url = rpcUrl.toNativeUtf8(allocator: arena);
      final addr = _toNative(arena, address);
      final out = arena<Pointer<aa_signer_t>>();
      checkStatus(_bindings.aa_signer_rpc(url.cast(), addr, out));
      return Signer._(out.value, null);
    });
  }

  /// A custom signer backed by a Dart [SignerImpl] (an HSM, MPC service, Privy,
  /// an embedded wallet, ...).
  ///
  /// The impl's methods run on the isolate that created the signer, so use the
  /// account it backs on that same isolate.
  factory Signer.custom(SignerImpl impl) {
    final bridge = _CustomSignerBridge(impl);
    final out = calloc<Pointer<aa_signer_t>>();
    try {
      final status = _bindings.aa_signer_custom(bridge.vtable, nullptr, out);
      if (status != aa_status.AA_OK) {
        bridge.close();
        throw AaException(status.value, lastErrorMessage());
      }
      return Signer._(out.value, bridge);
    } finally {
      calloc.free(out);
    }
  }

  Pointer<aa_signer_t> _ptr;
  _CustomSignerBridge? _bridge;
  bool _disposed = false;

  static final Finalizer<_SignerToken> _finalizer =
      Finalizer<_SignerToken>((t) => t.destroy());

  Pointer<aa_signer_t> get _handle {
    if (_disposed) throw StateError('Signer has been disposed');
    return _ptr;
  }

  /// Sign an EIP-7702 authorization tuple `(chainId, address, nonce)`.
  ///
  /// Works on any signer. Custom signers that set
  /// [SignerImpl.providesSignAuthorization] sign it natively; otherwise the SDK
  /// hashes `keccak256(0x05 || rlp([chainId, address, nonce]))` and signs that.
  Authorization signAuthorization(int chainId, Uint8List address, int nonce) {
    if (address.length != 20) {
      throw ArgumentError.value(address.length, 'address', 'address must be 20 bytes');
    }
    return using((arena) {
      final addr = _toNative(arena, address);
      final out = arena<aa_authorization_t>();
      checkStatus(
          _bindings.aa_signer_sign_authorization(_handle, chainId, addr, nonce, out));
      final a = out.ref;
      return Authorization(
        chainId: a.chain_id,
        address: _readArray(a.address, 20),
        nonce: a.nonce,
        yParity: a.y_parity,
        r: _readArray(a.r, 32),
        s: _readArray(a.s, 32),
      );
    });
  }

  /// Release the signer. Idempotent; safe to call more than once.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _finalizer.detach(this);
    _bindings.aa_signer_destroy(_ptr);
    _bridge?.close();
    _bridge = null;
  }

  /// Alias for [dispose].
  void close() => dispose();
}

/// GC-time cleanup for a [Signer] that was never disposed. Holds no reference
/// to the Signer itself so the object can be collected.
class _SignerToken {
  _SignerToken(this.ptr, this.bridge);

  final Pointer<aa_signer_t> ptr;
  final _CustomSignerBridge? bridge;

  void destroy() {
    _bindings.aa_signer_destroy(ptr);
    bridge?.close();
  }
}
