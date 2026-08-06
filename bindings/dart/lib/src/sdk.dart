/// The native-handle types (Signer, Context, Account, UserOp) and the callback
/// bridges that back them. They are composed as parts of one library so they
/// can share the library-private native pointers they hand to each other.
library;

import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'error.dart';
import 'ffi/aa_bindings.g.dart';
import 'native_loader.dart';
import 'types.dart';

part 'custom_signer.dart';
part 'signer.dart';
part 'context.dart';
part 'account.dart';
part 'userop.dart';
part 'transport.dart';
part 'account_async.dart';

/// The loaded native bindings.
AaBindings get _bindings => NativeLibrary.instance.bindings;

/// Copy [bytes] into native memory owned by [alloc]. Returns [nullptr] for an
/// empty list, matching the "nil pointer for empty" convention of the C ABI.
Pointer<Uint8> _toNative(Allocator alloc, List<int> bytes) {
  if (bytes.isEmpty) return nullptr;
  final p = alloc<Uint8>(bytes.length);
  p.asTypedList(bytes.length).setAll(0, bytes);
  return p;
}

/// Read [n] bytes from an inline C array field (e.g. `aa_authorization_t.r`).
Uint8List _readArray(Array<Uint8> array, int n) {
  final out = Uint8List(n);
  for (var i = 0; i < n; i++) {
    out[i] = array[i];
  }
  return out;
}
