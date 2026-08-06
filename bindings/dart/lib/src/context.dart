part of 'sdk.dart';

/// The SDK entry point: RPC endpoints, chain, and middleware, from which
/// accounts are created.
///
/// Create it with [Context.create], make accounts with [newAccount] /
/// [newAccount7702], and [dispose] it when finished. An account keeps its
/// context alive, so a context may be disposed once all its accounts are.
class Context implements Finalizable {
  Context._(this._ptr, this._httpBridge) {
    _finalizer.attach(this, _ContextToken(_ptr), detach: this);
  }

  /// Create a context for a ZeroDev [projectId].
  ///
  /// [rpcUrl] is the node endpoint for chain reads (empty = derived from the
  /// project and chain). [bundlerUrl] is the bundler/paymaster endpoint (empty
  /// = derived). [chainId] defaults to Sepolia (11155111). [gas] and
  /// [paymaster] select the built-in ZeroDev middleware; pass
  /// [PaymasterMiddleware.none] to send unsponsored.
  factory Context.create(
    String projectId, {
    String rpcUrl = '',
    String bundlerUrl = '',
    int chainId = 11155111,
    GasMiddleware gas = GasMiddleware.zeroDev,
    PaymasterMiddleware paymaster = PaymasterMiddleware.zeroDev,
  }) {
    final ctxPtr = using((arena) {
      final out = arena<Pointer<aa_context_t>>();
      checkStatus(_bindings.aa_context_create(
        projectId.toNativeUtf8(allocator: arena).cast(),
        rpcUrl.toNativeUtf8(allocator: arena).cast(),
        bundlerUrl.toNativeUtf8(allocator: arena).cast(),
        chainId,
        out,
      ));
      return out.value;
    });

    final ctx = Context._(ctxPtr, null);
    try {
      // Wire the built-in ZeroDev middleware by its exported symbol.
      if (gas == GasMiddleware.zeroDev) {
        final fn = NativeLibrary.instance.dylib
            .lookup<NativeFunction<aa_gas_price_fnFunction>>('aa_gas_zerodev');
        checkStatus(_bindings.aa_context_set_gas_middleware(ctxPtr, fn));
      }
      if (paymaster == PaymasterMiddleware.zeroDev) {
        final fn = NativeLibrary.instance.dylib
            .lookup<NativeFunction<aa_paymaster_fnFunction>>('aa_paymaster_zerodev');
        checkStatus(_bindings.aa_context_set_paymaster_middleware(ctxPtr, fn));
      }
    } catch (_) {
      ctx.dispose();
      rethrow;
    }
    return ctx;
  }

  Pointer<aa_context_t> _ptr;
  _HttpTransportBridge? _httpBridge;
  bool _disposed = false;

  static final Finalizer<_ContextToken> _finalizer =
      Finalizer<_ContextToken>((t) => t.destroy());

  Pointer<aa_context_t> get _handle {
    if (_disposed) throw StateError('Context has been disposed');
    return _ptr;
  }

  /// Create a Kernel smart account owned by [signer].
  ///
  /// [index] selects among the signer's counterfactual accounts (default 0).
  /// [address], when given, pins the account's sender to that 20-byte address
  /// — the migration path for accounts whose original CREATE2 inputs this SDK
  /// cannot reproduce; leave it null for the standard counterfactual flow.
  Account newAccount(
    Signer signer, {
    KernelVersion version = KernelVersion.v3_3,
    int index = 0,
    Uint8List? address,
  }) {
    if (address != null && address.length != 20) {
      throw ArgumentError.value(address.length, 'address', 'address must be 20 bytes');
    }
    return using((arena) {
      final out = arena<Pointer<aa_account_t>>();
      final addr = address == null ? nullptr : _toNative(arena, address);
      checkStatus(_bindings.aa_account_create(
        _handle,
        signer._handle,
        aa_kernel_version.fromValue(version.value),
        index,
        addr,
        out,
      ));
      return Account._(out.value, this, signer);
    });
  }

  /// Create an EIP-7702 account whose address IS [signer]'s EOA — no CREATE2,
  /// no index. The first UserOperation signs an authorization delegating the
  /// EOA to the Kernel implementation for [version].
  Account newAccount7702(
    Signer signer, {
    KernelVersion version = KernelVersion.v3_3,
  }) {
    return using((arena) {
      final out = arena<Pointer<aa_account_t>>();
      checkStatus(_bindings.aa_context_new_account_7702(
        _handle,
        signer._handle,
        aa_kernel_version.fromValue(version.value),
        out,
      ));
      return Account._(out.value, this, signer);
    });
  }

  /// Route all HTTP through [transport] instead of the SDK's built-in client.
  ///
  /// Useful on iOS, where the built-in TLS client cannot initialize. See
  /// [HttpTransport] for the contract.
  void setHttpTransport(HttpTransport transport) {
    final bridge = _HttpTransportBridge(transport);
    try {
      checkStatus(_bindings.aa_context_set_http_transport(
          _handle, bridge.callback.nativeFunction, nullptr));
    } catch (_) {
      bridge.close();
      rethrow;
    }
    _httpBridge?.close();
    _httpBridge = bridge;
  }

  /// Release the context. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _finalizer.detach(this);
    _bindings.aa_context_destroy(_ptr);
    _httpBridge?.close();
    _httpBridge = null;
  }

  /// Alias for [dispose].
  void close() => dispose();
}

/// GC-time cleanup for a [Context] that was never disposed.
class _ContextToken {
  _ContextToken(this.ptr);

  final Pointer<aa_context_t> ptr;

  void destroy() => _bindings.aa_context_destroy(ptr);
}
