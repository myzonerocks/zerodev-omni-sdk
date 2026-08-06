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

/// Thrown by [HttpClientTransport] when a request fails.
class HttpTransportException implements Exception {
  /// Wrap a failure [message].
  const HttpTransportException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'HttpTransportException: $message';
}

/// A concrete [HttpTransport] backed by a Dart `HttpClient` running on a
/// dedicated worker isolate — the Dart counterpart of the Swift binding's
/// URLSession transport, for the platforms where the built-in TLS client can't
/// run (notably iOS/Android under Flutter).
///
/// The SDK's HTTP callback is synchronous. [send] issues the request on the
/// worker isolate and blocks the calling isolate — on a native condition
/// variable, not by spinning — until the response arrives, so it satisfies the
/// C contract without ever running the request on the calling isolate's event
/// loop. Because it blocks, install and use it on a background isolate (in
/// Flutter, wrap your context and sends in `Isolate.run` / `compute`) so the UI
/// isolate stays responsive:
///
/// ```dart
/// final receiptJson = await Isolate.run(() async {
///   final ctx = Context.create(projectId, chainId: 11155111);
///   final transport = await HttpClientTransport.create();
///   ctx.setHttpTransport(transport.send);
///   final signer = Signer.generate();
///   final account = ctx.newAccount(signer);
///   try {
///     final hash = account.sendUserOp([Call(target: account.getAddress())]);
///     return account.waitForUserOperationReceipt(hash).json;
///   } finally {
///     account.dispose(); signer.dispose(); ctx.dispose(); transport.dispose();
///   }
/// });
/// ```
class HttpClientTransport {
  HttpClientTransport._(this._worker, this._workerPort, this._responses);

  /// Spawn the worker isolate and its `HttpClient`.
  static Future<HttpClientTransport> create() async {
    final setup = ReceivePort();
    final worker = await Isolate.spawn(_httpWorkerMain, setup.sendPort,
        debugName: 'zerodev-http');
    final workerPort = await setup.first as SendPort;
    setup.close();
    return HttpClientTransport._(worker, workerPort, Mailbox());
  }

  final Isolate _worker;
  final SendPort _workerPort;
  final Mailbox _responses;
  bool _closed = false;

  /// POST [body] to [url] and return the response bytes, blocking until done.
  /// This is an [HttpTransport]; pass it to [Context.setHttpTransport].
  Uint8List send(String url, Uint8List body) {
    if (_closed) {
      throw const HttpTransportException('transport is closed');
    }
    _workerPort.send([url, body, _responses.asSendable]);
    // take() returns a view into a native buffer freed when it is collected, so
    // copy out (sublist) before the view goes out of scope.
    final framed = _responses.take(); // blocks the OS thread, not by polling
    if (framed.isEmpty) {
      throw const HttpTransportException('empty response');
    }
    final body0 = framed.sublist(1);
    if (framed[0] != 0) {
      throw HttpTransportException(utf8.decode(body0));
    }
    return body0;
  }

  /// Shut the worker isolate down. Idempotent.
  void dispose() {
    if (_closed) return;
    _closed = true;
    _workerPort.send('shutdown');
    _worker.kill(priority: Isolate.beforeNextEvent);
  }
}

/// Worker-isolate entrypoint: owns an `HttpClient` and answers POST requests,
/// putting each response into the caller's mailbox framed with a status byte
/// (0 = ok, 1 = error) so the caller can block on it and unframe the result.
void _httpWorkerMain(SendPort setup) {
  final client = HttpClient();
  final port = ReceivePort();
  setup.send(port.sendPort);

  port.listen((message) async {
    if (message == 'shutdown') {
      port.close();
      client.close(force: true);
      return;
    }
    final request = message as List;
    final url = request[0] as String;
    final body = request[1] as Uint8List;
    final mailbox = (request[2] as Sendable<Mailbox>).materialize();
    try {
      final req = await client.postUrl(Uri.parse(url));
      req.headers.contentType = ContentType('application', 'json');
      req.add(body);
      final resp = await req.close();
      // copy: true — the stream's chunk buffers may be reused after each event.
      final builder = BytesBuilder();
      await for (final chunk in resp) {
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      final framed = Uint8List(bytes.length + 1)..setRange(1, bytes.length + 1, bytes);
      framed[0] = 0;
      mailbox.put(framed);
    } catch (e) {
      final err = utf8.encode(e.toString());
      final framed = Uint8List(err.length + 1)..setRange(1, err.length + 1, err);
      framed[0] = 1;
      mailbox.put(framed);
    }
  });
}
