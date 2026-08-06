import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zerodev_aa/zerodev_aa.dart';

void main() {
  test('HttpClientTransport round-trips a POST synchronously', () async {
    // A local echo server on the main isolate. The transport call runs on a
    // background isolate, so blocking there leaves this isolate free to serve.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final body = await req.fold<List<int>>(<int>[], (b, d) => b..addAll(d));
      req.response.headers.contentType = ContentType('application', 'json');
      req.response.add(utf8.encode('{"len":${body.length}}'));
      await req.response.close();
    });
    final url = 'http://127.0.0.1:${server.port}/rpc';

    final response = await Isolate.run(() async {
      final transport = await HttpClientTransport.create();
      try {
        return transport.send(url, Uint8List.fromList(utf8.encode('hello')));
      } finally {
        transport.dispose();
      }
    });

    await server.close(force: true);
    expect(utf8.decode(response), '{"len":5}');
  });

  test('HttpClientTransport surfaces request failures', () async {
    final outcome = await Isolate.run(() async {
      final transport = await HttpClientTransport.create();
      try {
        // Nothing is listening on port 1 — the request is refused.
        transport.send('http://127.0.0.1:1/', Uint8List(0));
        return 'no-throw';
      } on HttpTransportException {
        return 'threw';
      } finally {
        transport.dispose();
      }
    });
    expect(outcome, 'threw');
  });
}
