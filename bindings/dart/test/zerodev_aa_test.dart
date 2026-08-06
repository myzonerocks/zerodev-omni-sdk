import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zerodev_aa/zerodev_aa.dart';

/// A deterministic custom signer with a fixed address, for offline tests.
class _FixedSigner extends SignerImpl {
  _FixedSigner(this.address);

  final Uint8List address;

  @override
  Uint8List getAddress() => address;

  @override
  Uint8List signHash(Uint8List hash) => Uint8List(65);

  @override
  Uint8List signMessage(Uint8List message) => Uint8List(65);

  @override
  Uint8List signTypedDataHash(Uint8List hash) => Uint8List(65);
}

/// A custom signer that counts callback invocations, for verifying which C
/// path (native vtable slot vs sign_hash fallback) the SDK takes.
class _CountingSigner extends SignerImpl {
  _CountingSigner({required this.address, this.provideAuth = false, this.auth});

  final Uint8List address;
  final bool provideAuth;
  final Authorization? auth;
  int signHashCalls = 0;
  int signAuthCalls = 0;

  @override
  Uint8List getAddress() => address;
  @override
  Uint8List signHash(Uint8List hash) {
    signHashCalls++;
    return Uint8List(65);
  }

  @override
  Uint8List signMessage(Uint8List message) => Uint8List(65);
  @override
  Uint8List signTypedDataHash(Uint8List hash) => Uint8List(65);

  @override
  bool get providesSignAuthorization => provideAuth;
  @override
  Authorization signAuthorization(int chainId, Uint8List address, int nonce) {
    signAuthCalls++;
    return auth!;
  }
}

Uint8List _bytes(int n, int fill) => Uint8List(n)..fillRange(0, n, fill);

void main() {
  group('hex', () {
    test('encode/decode round-trips', () {
      final bytes = Uint8List.fromList([0x00, 0x0f, 0xa0, 0xff, 0x10]);
      expect(hexEncode(bytes), '000fa0ff10');
      expect(hexDecode('0x000fa0ff10'), bytes);
      expect(hexDecode('000FA0FF10'), bytes); // no prefix, uppercase
    });

    test('rejects odd length and non-hex', () {
      expect(() => hexDecode('0xabc'), throwsA(isA<AaException>()));
      expect(() => hexDecode('zz'), throwsA(isA<AaException>()));
    });
  });

  group('types', () {
    test('Address requires 20 bytes and round-trips hex', () {
      expect(() => Address(_bytes(19, 1)), throwsArgumentError);
      final a = Address(_bytes(20, 0xab));
      expect(a.toHex(), '0x${'ab' * 20}');
      expect(Address.fromHex(a.toHex()), a); // value equality
      expect(a.hashCode, Address.fromHex(a.toHex()).hashCode);
    });

    test('Hash reports isZero and requires 32 bytes', () {
      expect(Hash(Uint8List(32)).isZero, isTrue);
      expect(Hash(_bytes(32, 1)).isZero, isFalse);
      expect(() => Hash(_bytes(31, 0)), throwsArgumentError);
    });

    test('UserOperationReceipt parses fields and success', () {
      final r = UserOperationReceipt.fromJson(
          '{"userOpHash":"0x1","sender":"0xabc","success":true}');
      expect(r.userOpHash, '0x1');
      expect(r.sender, '0xabc');
      expect(r.success, isTrue);
      expect(r.reason, isNull);
    });
  });

  group('errors', () {
    test('AaErrorCode maps values to names', () {
      expect(AaErrorCode.fromValue(13), AaErrorCode.sendUserOpFailed);
      expect(AaErrorCode.fromValue(999), isNull);
      expect(AaException(24, 'bad key').toString(),
          'InvalidSigner (code 24): bad key');
    });
  });

  group('signer + account (offline)', () {
    test('generate + local signers create and dispose', () {
      final gen = Signer.generate();
      addTearDown(gen.dispose);
      final local = Signer.local(_bytes(32, 7));
      addTearDown(local.dispose);
      expect(() => Signer.local(_bytes(31, 7)), throwsArgumentError);
    });

    test('counterfactual address is stable and 20 bytes', () {
      final signer = Signer.generate();
      final ctx = Context.create('test-project',
          chainId: 11155111, paymaster: PaymasterMiddleware.none);
      final account = ctx.newAccount(signer);
      addTearDown(() {
        account.dispose();
        ctx.dispose();
        signer.dispose();
      });

      final a1 = account.getAddress();
      final a2 = account.getAddress();
      expect(a1.bytes.length, 20);
      expect(a1, a2); // deterministic
    });

    test('pinned address is returned verbatim; wrong length rejected', () {
      final signer = Signer.generate();
      final ctx = Context.create('test-project',
          paymaster: PaymasterMiddleware.none);
      addTearDown(() {
        ctx.dispose();
        signer.dispose();
      });

      final pinned = _bytes(20, 0x42);
      final account = ctx.newAccount(signer, address: pinned);
      addTearDown(account.dispose);
      expect(account.getAddress().bytes, pinned);

      expect(() => ctx.newAccount(signer, address: _bytes(19, 0x42)),
          throwsArgumentError);
    });

    test('7702 account address equals the custom signer EOA', () {
      final eoa = _bytes(20, 0x11);
      final signer = Signer.custom(_FixedSigner(eoa));
      final ctx = Context.create('test-project',
          paymaster: PaymasterMiddleware.none);
      final account = ctx.newAccount7702(signer);
      addTearDown(() {
        account.dispose();
        ctx.dispose();
        signer.dispose();
      });
      expect(account.getAddress().bytes, eoa);
    });

    test('using a disposed signer throws', () {
      final signer = Signer.generate();
      signer.dispose();
      expect(() => signer.signAuthorization(1, _bytes(20, 0), 0),
          throwsStateError);
    });
  });

  group('custom signer EIP-7702 (offline)', () {
    test('native signAuthorization is used when provided', () {
      final expected = Authorization(
        chainId: 11155111,
        address: _bytes(20, 0xaa),
        nonce: 7,
        yParity: 1,
        r: _bytes(32, 1),
        s: _bytes(32, 2),
      );
      final impl =
          _CountingSigner(address: _bytes(20, 1), provideAuth: true, auth: expected);
      final signer = Signer.custom(impl);
      addTearDown(signer.dispose);

      final got = signer.signAuthorization(11155111, _bytes(20, 0xaa), 7);
      expect(impl.signAuthCalls, 1);
      expect(impl.signHashCalls, 0);
      expect(got, expected); // Authorization value equality
    });

    test('falls back to signHash when signAuthorization is not provided', () {
      final impl = _CountingSigner(address: _bytes(20, 1));
      final signer = Signer.custom(impl);
      addTearDown(signer.dispose);

      final got = signer.signAuthorization(11155111, _bytes(20, 0xaa), 7);
      expect(impl.signAuthCalls, 0);
      expect(impl.signHashCalls, greaterThanOrEqualTo(1));
      expect(got.chainId, 11155111);
      expect(got.nonce, 7);
    });

    test('signAuthorization on a generated signer is well-formed', () {
      final signer = Signer.generate();
      addTearDown(signer.dispose);

      final address = _bytes(20, 0xcd);
      final auth = signer.signAuthorization(11155111, address, 3);
      expect(auth.chainId, 11155111);
      expect(auth.address, address);
      expect(auth.nonce, 3);
      expect(auth.yParity, anyOf(0, 1));
      expect(auth.r.length, 32);
      expect(auth.s.length, 32);
      expect(auth.r.any((b) => b != 0), isTrue); // non-zero
      expect(auth.s.any((b) => b != 0), isTrue);
    });

    test('Call and Authorization have value equality', () {
      final target = Address(_bytes(20, 9));
      expect(Call(target: target), Call(target: target));
      expect(Call(target: target).hashCode, Call(target: target).hashCode);

      Authorization a() => Authorization.fromCompactSignature(
            chainId: 1,
            address: _bytes(20, 3),
            nonce: 0,
            signature: _bytes(65, 4)..[64] = 27,
          );
      expect(a(), a());
      expect(a().yParity, 0); // v=27 -> yParity 0
    });
  });
}
