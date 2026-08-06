import 'dart:convert';
import 'dart:typed_data';

import 'error.dart';
import 'hex.dart';

/// A 20-byte Ethereum address.
///
/// Value type: two addresses with the same bytes are equal and hash alike, so
/// it can be used as a map key or set member.
class Address {
  /// Wrap exactly 20 [bytes].
  Address(this.bytes) {
    if (bytes.length != 20) {
      throw ArgumentError.value(bytes.length, 'bytes', 'Address must be 20 bytes');
    }
  }

  /// Parse a `0x`/`0X`-prefixed (or bare) hex string of 20 bytes.
  factory Address.fromHex(String hex) {
    final decoded = hexDecode(hex);
    if (decoded.length != 20) {
      throw AaException(
        AaErrorCode.invalidHex.code,
        'address hex must decode to 20 bytes, got ${decoded.length}',
      );
    }
    return Address(decoded);
  }

  /// The raw 20 bytes.
  final Uint8List bytes;

  /// The `0x`-prefixed lowercase hex form.
  String toHex() => '0x${hexEncode(bytes)}';

  @override
  String toString() => toHex();

  @override
  bool operator ==(Object other) =>
      other is Address && _bytesEqual(bytes, other.bytes);

  @override
  int get hashCode => Object.hashAll(bytes);
}

/// A 32-byte hash (a UserOperation hash, tx hash, or typed-data digest).
class Hash {
  /// Wrap exactly 32 [bytes].
  Hash(this.bytes) {
    if (bytes.length != 32) {
      throw ArgumentError.value(bytes.length, 'bytes', 'Hash must be 32 bytes');
    }
  }

  /// Parse a `0x`/`0X`-prefixed (or bare) hex string of 32 bytes.
  factory Hash.fromHex(String hex) {
    final decoded = hexDecode(hex);
    if (decoded.length != 32) {
      throw AaException(AaErrorCode.invalidHex.code,
          'hash hex must decode to 32 bytes, got ${decoded.length}');
    }
    return Hash(decoded);
  }

  /// The raw 32 bytes.
  final Uint8List bytes;

  /// The `0x`-prefixed lowercase hex form.
  String toHex() => '0x${hexEncode(bytes)}';

  /// Whether every byte is zero.
  bool get isZero => bytes.every((b) => b == 0);

  @override
  String toString() => toHex();

  @override
  bool operator ==(Object other) => other is Hash && _bytesEqual(bytes, other.bytes);

  @override
  int get hashCode => Object.hashAll(bytes);
}

/// The Kernel smart account version. Only v3.3 is defined, and it is the only
/// version supporting EIP-7702.
enum KernelVersion {
  v3_3;

  /// The `aa_kernel_version` value.
  int get value => index;
}

/// The gas-pricing middleware provider passed when creating a [Context].
enum GasMiddleware {
  /// ZeroDev: `zd_getUserOperationGasPrice`.
  zeroDev,
}

/// The paymaster sponsorship provider passed when creating a [Context].
enum PaymasterMiddleware {
  /// No paymaster — the account pays its own gas.
  none,

  /// ZeroDev: `pm_getPaymasterStubData` / `pm_getPaymasterData`.
  zeroDev,
}

/// One call in a UserOperation.
class Call {
  /// A call to [target], transferring [value] wei (32-byte big-endian, default
  /// zero) with [calldata] (default empty).
  Call({required this.target, Uint8List? value, Uint8List? calldata})
      : value = value ?? Uint8List(32),
        calldata = calldata ?? Uint8List(0) {
    if (this.value.length != 32) {
      throw ArgumentError.value(
          this.value.length, 'value', 'value must be 32 bytes (big-endian u256)');
    }
  }

  /// The call target.
  final Address target;

  /// The value in wei, as 32 big-endian bytes.
  final Uint8List value;

  /// The calldata bytes (may be empty).
  final Uint8List calldata;
}

/// An EIP-7702 authorization tuple.
///
/// [yParity], [r], and [s] sign `keccak256(0x05 || rlp([chainId, address,
/// nonce]))`, delegating the EOA's code to the Kernel implementation at
/// [address]. Produced by `Signer.signAuthorization` and attached to the first
/// UserOperation of an EIP-7702 account.
class Authorization {
  /// Build a tuple. [address] must be 20 bytes; [r] and [s] must be 32 bytes.
  Authorization({
    required this.chainId,
    required this.address,
    required this.nonce,
    required this.yParity,
    required this.r,
    required this.s,
  }) {
    if (address.length != 20) {
      throw ArgumentError.value(address.length, 'address', 'must be 20 bytes');
    }
    if (r.length != 32) throw ArgumentError.value(r.length, 'r', 'must be 32 bytes');
    if (s.length != 32) throw ArgumentError.value(s.length, 's', 'must be 32 bytes');
  }

  /// Chain ID the authorization is valid on (0 = any chain).
  final int chainId;

  /// Delegation target (Kernel implementation address), 20 bytes.
  final Uint8List address;

  /// EOA nonce at signing time.
  final int nonce;

  /// Signature y-parity (0 or 1).
  final int yParity;

  /// Signature r, 32 bytes.
  final Uint8List r;

  /// Signature s, 32 bytes.
  final Uint8List s;
}

/// Current gas prices, filled by a gas-pricing middleware.
class GasPrices {
  /// Prices in wei.
  const GasPrices({required this.maxFeePerGas, required this.maxPriorityFeePerGas});

  /// The max fee per gas, in wei.
  final int maxFeePerGas;

  /// The max priority fee per gas, in wei.
  final int maxPriorityFeePerGas;
}

/// The result a paymaster middleware returns to sponsor a UserOperation.
class PaymasterData {
  /// Sponsor with [paymaster] (20 bytes), the two gas limits, and [data].
  PaymasterData({
    required this.paymaster,
    required this.verificationGasLimit,
    required this.postOpGasLimit,
    Uint8List? data,
  }) : data = data ?? Uint8List(0) {
    if (paymaster.length != 20) {
      throw ArgumentError.value(paymaster.length, 'paymaster', 'must be 20 bytes');
    }
  }

  /// The paymaster contract address, 20 bytes.
  final Uint8List paymaster;

  /// The paymaster verification gas limit.
  final int verificationGasLimit;

  /// The paymaster post-op gas limit.
  final int postOpGasLimit;

  /// The paymaster data bytes.
  final Uint8List data;
}

/// A parsed `eth_getUserOperationReceipt` response.
///
/// Holds the raw [json] and exposes the ERC-4337 fields as typed getters.
/// Use [asMap] for the fully decoded JSON object.
class UserOperationReceipt {
  /// Wrap a raw receipt [json] string.
  UserOperationReceipt(this.json);

  /// Parse a raw receipt [json] string (alias for the constructor, matching the
  /// other bindings' `fromJson`).
  factory UserOperationReceipt.fromJson(String json) => UserOperationReceipt(json);

  /// The raw JSON response string.
  final String json;

  Map<String, dynamic>? _cache;
  bool _parsed = false;

  /// The decoded JSON object, or null if the body is not a JSON object.
  Map<String, dynamic>? get asMap {
    if (!_parsed) {
      _parsed = true;
      try {
        final v = jsonDecode(json);
        if (v is Map<String, dynamic>) _cache = v;
      } catch (_) {
        _cache = null;
      }
    }
    return _cache;
  }

  String? _string(String key) {
    final v = asMap?[key];
    return v is String ? v : null;
  }

  /// Hash of the user operation.
  String get userOpHash => _string('userOpHash') ?? '';

  /// Entry point address.
  String get entryPoint => _string('entryPoint') ?? '';

  /// Sender (smart account) address.
  String get sender => _string('sender') ?? '';

  /// Anti-replay nonce, as a hex string.
  String get nonce => _string('nonce') ?? '';

  /// Paymaster address, if the operation was sponsored.
  String? get paymaster => _string('paymaster');

  /// Actual gas cost, as a hex string.
  String get actualGasCost => _string('actualGasCost') ?? '';

  /// Actual gas used, as a hex string.
  String get actualGasUsed => _string('actualGasUsed') ?? '';

  /// Whether the operation's execution succeeded.
  bool get success => asMap?['success'] == true;

  /// Revert reason, if the operation failed.
  String? get reason => _string('reason');

  /// Logs emitted during execution.
  List<dynamic> get logs {
    final v = asMap?['logs'];
    return v is List ? v : const [];
  }

  /// The transaction receipt of the operation's execution.
  Map<String, dynamic>? get receipt {
    final v = asMap?['receipt'];
    return v is Map<String, dynamic> ? v : null;
  }
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
