import 'dart:typed_data';

import 'error.dart';

const _hexChars = '0123456789abcdef';

/// Lowercase hex for [bytes], without a `0x` prefix.
String hexEncode(List<int> bytes) {
  final out = StringBuffer();
  for (final b in bytes) {
    out.write(_hexChars[(b >> 4) & 0xF]);
    out.write(_hexChars[b & 0xF]);
  }
  return out.toString();
}

/// Decode [hex] (an optional `0x`/`0X` prefix, then hex digit pairs) to bytes.
///
/// Throws [AaException] with [AaErrorCode.invalidHex] on an odd length or a
/// non-hex character — matching the error the other bindings raise.
Uint8List hexDecode(String hex) {
  var s = hex;
  if (s.startsWith('0x') || s.startsWith('0X')) s = s.substring(2);
  if (s.length.isOdd) {
    throw AaException(AaErrorCode.invalidHex.code, 'hex string has an odd length');
  }
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = (_digit(s, i * 2) << 4) | _digit(s, i * 2 + 1);
  }
  return out;
}

int _digit(String s, int i) {
  final c = s.codeUnitAt(i);
  if (c >= 0x30 && c <= 0x39) return c - 0x30; // 0-9
  if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10; // a-f
  if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10; // A-F
  throw AaException(
    AaErrorCode.invalidHex.code,
    "invalid hex character '${s[i]}' at index $i",
  );
}
