import 'dart:ffi';
import 'dart:io';

import 'ffi/aa_bindings.g.dart';

/// Loads `libzerodev_aa` and exposes the generated FFI entrypoints.
///
/// The search order mirrors the other bindings (see `bindings/python`):
///
///   1. an explicit path passed to [open];
///   2. `$ZERODEV_LIB_DIR/<lib>`;
///   3. `$ZERODEV_SDK_ROOT/zig-out/lib/<lib>`;
///   4. `zig-out/lib/<lib>` found by walking up from the current directory
///      (an SDK source checkout: tests, examples, `dart run`);
///   5. the plain library name, letting the OS loader search its own paths
///      (Android `jniLibs`, an rpath, `LD_LIBRARY_PATH`, `DYLD_*`, and so on).
///
/// On iOS the library is statically linked into the app binary, so its symbols
/// are already in the running process and there is no file to open.
class NativeLibrary {
  const NativeLibrary._(this.dylib, this.bindings, this.path);

  /// The opened dynamic library, for looking up symbols (e.g. the built-in
  /// middleware function pointers) not surfaced as [bindings] methods.
  final DynamicLibrary dylib;

  /// The generated FFI bindings, ready to call.
  final AaBindings bindings;

  /// The resolved library path, or `"<process>"` when linked into the binary.
  final String path;

  static NativeLibrary? _instance;

  /// The process-wide instance, loaded on first use.
  static NativeLibrary get instance => _instance ??= open();

  /// Load `libzerodev_aa`, optionally from an explicit [path].
  ///
  /// The result is cached as [instance] only when no explicit [path] is given.
  static NativeLibrary open({String? path}) {
    if (Platform.isIOS) {
      // Statically linked into the host app; symbols are already in-process.
      final dylib = DynamicLibrary.process();
      return _instance ??= NativeLibrary._(dylib, AaBindings(dylib), '<process>');
    }

    final resolved = path ?? _resolve();
    final dylib = DynamicLibrary.open(resolved);
    final lib = NativeLibrary._(dylib, AaBindings(dylib), resolved);
    if (path == null) _instance ??= lib;
    return lib;
  }

  /// The platform library file name: `libzerodev_aa.dylib` / `.so` /
  /// `zerodev_aa.dll`.
  static String libFileName() {
    if (Platform.isMacOS) return 'libzerodev_aa.dylib';
    if (Platform.isWindows) return 'zerodev_aa.dll';
    return 'libzerodev_aa.so'; // Linux, Android
  }

  /// First existing candidate, else the bare name for the OS loader to find.
  static String _resolve() {
    for (final candidate in _candidatePaths()) {
      if (File(candidate).existsSync()) return candidate;
    }
    return libFileName();
  }

  static List<String> _candidatePaths() {
    final name = libFileName();
    final sep = Platform.pathSeparator;
    final out = <String>[];

    final libDir = Platform.environment['ZERODEV_LIB_DIR'];
    if (libDir != null && libDir.isNotEmpty) {
      out.add('$libDir$sep$name');
    }

    final sdkRoot = Platform.environment['ZERODEV_SDK_ROOT'];
    if (sdkRoot != null && sdkRoot.isNotEmpty) {
      out.add('$sdkRoot${sep}zig-out${sep}lib$sep$name');
    }

    // Walk up from the current directory looking for a zig-out/lib build. Any
    // working directory inside the SDK checkout (bindings/dart, example, test)
    // reaches the root this way.
    for (var dir = Directory.current;; dir = dir.parent) {
      out.add('${dir.path}${sep}zig-out${sep}lib$sep$name');
      if (dir.parent.path == dir.path) break; // filesystem root
    }

    return out;
  }
}
