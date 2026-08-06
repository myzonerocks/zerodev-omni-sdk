part of 'sdk.dart';

/// A host-supplied signer: implement this to sign with your own key management
/// — Privy, an HSM, an MPC service, or an embedded wallet — and pass an
/// instance to [Signer.custom].
///
/// The SDK calls [signHash] to sign UserOperations; [signMessage] and
/// [signTypedDataHash] are there for host flows. Every method runs
/// synchronously on the isolate that created the signer, and any thrown error
/// is caught at the FFI boundary and reported to the caller as a signing
/// failure (it never unwinds across native code).
///
/// Extend this class to implement only the four required methods; override
/// [providesSignAuthorization] and [signAuthorization] to sign EIP-7702 tuples
/// natively.
///
/// Signing is synchronous: the SDK invokes these methods on the calling isolate
/// and cannot await. If your key material is only reachable asynchronously (a
/// remote wallet, an embedded provider), resolve it before the call — e.g. warm
/// a cache, then look it up synchronously here.
abstract class SignerImpl {
  /// Sign a 32-byte [hash], returning a 65-byte `r‖s‖v` signature.
  Uint8List signHash(Uint8List hash);

  /// Sign an arbitrary [message] (personal_sign), returning 65 bytes.
  Uint8List signMessage(Uint8List message);

  /// Sign a 32-byte EIP-712 typed-data [hash], returning 65 bytes.
  Uint8List signTypedDataHash(Uint8List hash);

  /// The signer's 20-byte address.
  Uint8List getAddress();

  /// Whether [signAuthorization] is implemented.
  ///
  /// When false (the default) the SDK signs EIP-7702 tuples by hashing
  /// `keccak256(0x05 || rlp([chainId, address, nonce]))` and calling
  /// [signHash]. Override to return true to have the SDK call
  /// [signAuthorization] instead.
  bool get providesSignAuthorization => false;

  /// Natively sign an EIP-7702 authorization tuple.
  ///
  /// Only called when [providesSignAuthorization] is true.
  Authorization signAuthorization(int chainId, Uint8List address, int nonce) =>
      throw UnimplementedError(
        'signAuthorization is not implemented; set providesSignAuthorization '
        'to true only when it is',
      );
}

/// The native callbacks and vtable backing a custom [Signer]. Held for the
/// signer's lifetime and released on dispose so the C side never calls a freed
/// trampoline.
class _CustomSignerBridge {
  _CustomSignerBridge(this._impl) {
    _signHash = NativeCallable<
        Int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>)>.isolateLocal(
      _onSignHash,
      exceptionalReturn: 1,
    );
    _signMessage = NativeCallable<
        Int Function(Pointer<Void>, Pointer<Uint8>, Size,
            Pointer<Uint8>)>.isolateLocal(_onSignMessage, exceptionalReturn: 1);
    _signTypedDataHash = NativeCallable<
        Int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>)>.isolateLocal(
      _onSignTypedDataHash,
      exceptionalReturn: 1,
    );
    _getAddress =
        NativeCallable<Int Function(Pointer<Void>, Pointer<Uint8>)>.isolateLocal(
      _onGetAddress,
      exceptionalReturn: 1,
    );
    _signAuthorization = NativeCallable<
        Int Function(Pointer<Void>, Uint64, Pointer<Uint8>, Uint64,
            Pointer<aa_authorization_t>)>.isolateLocal(
      _onSignAuthorization,
      exceptionalReturn: 1,
    );

    vtable = calloc<aa_signer_vtable>();
    vtable.ref.sign_hash = _signHash.nativeFunction;
    vtable.ref.sign_message = _signMessage.nativeFunction;
    vtable.ref.sign_typed_data_hash = _signTypedDataHash.nativeFunction;
    vtable.ref.get_address = _getAddress.nativeFunction;
    // Leave sign_hash's optional 5th slot null unless the impl provides it, so
    // the SDK uses its keccak(0x05||rlp)+sign_hash fallback otherwise.
    if (_impl.providesSignAuthorization) {
      vtable.ref.sign_authorization = _signAuthorization.nativeFunction;
    }
  }

  final SignerImpl _impl;

  /// The vtable handed to `aa_signer_custom`. Valid until [close].
  late final Pointer<aa_signer_vtable> vtable;

  late final NativeCallable<
      Int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>)> _signHash;
  late final NativeCallable<
      Int Function(Pointer<Void>, Pointer<Uint8>, Size,
          Pointer<Uint8>)> _signMessage;
  late final NativeCallable<
          Int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>)>
      _signTypedDataHash;
  late final NativeCallable<Int Function(Pointer<Void>, Pointer<Uint8>)>
      _getAddress;
  late final NativeCallable<
      Int Function(Pointer<Void>, Uint64, Pointer<Uint8>, Uint64,
          Pointer<aa_authorization_t>)> _signAuthorization;

  int _onSignHash(Pointer<Void> ctx, Pointer<Uint8> hash, Pointer<Uint8> sigOut) {
    try {
      final sig = _impl.signHash(Uint8List.fromList(hash.asTypedList(32)));
      if (sig.length != 65) return 1;
      sigOut.asTypedList(65).setAll(0, sig);
      return 0;
    } catch (_) {
      return 1;
    }
  }

  int _onSignMessage(
      Pointer<Void> ctx, Pointer<Uint8> msg, int msgLen, Pointer<Uint8> sigOut) {
    try {
      final sig = _impl.signMessage(Uint8List.fromList(msg.asTypedList(msgLen)));
      if (sig.length != 65) return 1;
      sigOut.asTypedList(65).setAll(0, sig);
      return 0;
    } catch (_) {
      return 1;
    }
  }

  int _onSignTypedDataHash(
      Pointer<Void> ctx, Pointer<Uint8> hash, Pointer<Uint8> sigOut) {
    try {
      final sig =
          _impl.signTypedDataHash(Uint8List.fromList(hash.asTypedList(32)));
      if (sig.length != 65) return 1;
      sigOut.asTypedList(65).setAll(0, sig);
      return 0;
    } catch (_) {
      return 1;
    }
  }

  int _onGetAddress(Pointer<Void> ctx, Pointer<Uint8> addrOut) {
    try {
      final addr = _impl.getAddress();
      if (addr.length != 20) return 1;
      addrOut.asTypedList(20).setAll(0, addr);
      return 0;
    } catch (_) {
      return 1;
    }
  }

  int _onSignAuthorization(Pointer<Void> ctx, int chainId, Pointer<Uint8> address,
      int nonce, Pointer<aa_authorization_t> out) {
    try {
      final auth = _impl.signAuthorization(
          chainId, Uint8List.fromList(address.asTypedList(20)), nonce);
      out.ref.chain_id = auth.chainId;
      out.ref.nonce = auth.nonce;
      out.ref.y_parity = auth.yParity;
      for (var i = 0; i < 20; i++) {
        out.ref.address[i] = auth.address[i];
      }
      for (var i = 0; i < 32; i++) {
        out.ref.r[i] = auth.r[i];
        out.ref.s[i] = auth.s[i];
      }
      return 0;
    } catch (_) {
      return 1;
    }
  }

  /// Close the callbacks and free the vtable. Idempotent.
  void close() {
    _signHash.close();
    _signMessage.close();
    _signTypedDataHash.close();
    _getAddress.close();
    _signAuthorization.close();
    calloc.free(vtable);
  }
}
