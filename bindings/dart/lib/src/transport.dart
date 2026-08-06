part of 'sdk.dart';

/// A synchronous HTTP transport: POST [body] to [url] and return the raw
/// response bytes, or throw to signal failure.
///
/// Install one with [Context.setHttpTransport] to route the SDK's requests
/// through your own HTTP stack instead of its built-in client — the Dart
/// equivalent of the Swift binding's URLSession transport.
///
/// The SDK calls this synchronously and expects the response before it returns,
/// so the function must block until the request completes and must run off the
/// UI isolate. On desktop the built-in client already works, so a transport is
/// only needed where that client cannot run — notably iOS, whose TLS lacks the
/// CA paths the built-in client needs.
typedef HttpTransport = Uint8List Function(String url, Uint8List body);

/// Bridges a Dart [HttpTransport] to the C `aa_http_fn`. Held while installed
/// on a context and released when replaced or the context is disposed, so the
/// SDK never calls a freed trampoline.
class _HttpTransportBridge {
  _HttpTransportBridge(this._transport) {
    callback = NativeCallable<aa_http_fnFunction>.isolateLocal(
      _onRequest,
      exceptionalReturn: 1,
    );
  }

  final HttpTransport _transport;
  late final NativeCallable<aa_http_fnFunction> callback;

  int _onRequest(
    Pointer<Void> ctx,
    Pointer<Char> url,
    Pointer<Char> body,
    int bodyLen,
    Pointer<Pointer<Char>> responseOut,
    Pointer<Size> responseLenOut,
  ) {
    try {
      final u = url.cast<Utf8>().toDartString();
      final b = Uint8List.fromList(body.cast<Uint8>().asTypedList(bodyLen));
      final response = _transport(u, b);
      // Allocate via aa_alloc (libc malloc) so the SDK can free it directly,
      // honouring the F-02 allocator contract without a free callback.
      final out = _bindings.aa_alloc(response.length).cast<Uint8>();
      if (out == nullptr) return 1;
      out.asTypedList(response.length).setAll(0, response);
      responseOut.value = out.cast();
      responseLenOut.value = response.length;
      return 0;
    } catch (_) {
      return 1;
    }
  }

  void close() => callback.close();
}
