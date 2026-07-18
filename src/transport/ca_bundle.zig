//! Mozilla CA roots baked into the binary, for iOS and Android where the http
//! client has no system certificate store to scan and TLS can't otherwise start.

const std = @import("std");
const http = std.http;
const Bundle = std.crypto.Certificate.Bundle;

const embedded_pem = @embedFile("cacert.pem");

/// Load the embedded roots into `client`. No-op when TLS is compiled out.
pub fn install(client: *http.Client, gpa: std.mem.Allocator, io: std.Io) !void {
    if (http.Client.disable_tls) return;
    const now = std.Io.Clock.real.now(io);
    try addCertsFromBytes(&client.ca_bundle, gpa, embedded_pem, now.toSeconds());
    // A set clock makes request() skip its system rescan.
    client.now = now;
}

/// Parse PEM certs from `encoded_bytes` into `cb`. Like addCertsFromFile, but
/// over a slice so it works on @embedFile data.
fn addCertsFromBytes(cb: *Bundle, gpa: std.mem.Allocator, encoded_bytes: []const u8, now_sec: i64) !void {
    const base64 = std.base64.standard.decoderWithIgnore(" \t\r\n");
    const begin_marker = "-----BEGIN CERTIFICATE-----";
    const end_marker = "-----END CERTIFICATE-----";

    var start_index: usize = 0;
    while (std.mem.findPos(u8, encoded_bytes, start_index, begin_marker)) |begin_marker_start| {
        const cert_start = begin_marker_start + begin_marker.len;
        const cert_end = std.mem.findPos(u8, encoded_bytes, cert_start, end_marker) orelse
            return error.MissingEndCertificateMarker;
        start_index = cert_end + end_marker.len;
        const encoded_cert = std.mem.trim(u8, encoded_bytes[cert_start..cert_end], " \t\r\n");
        const decoded_start: u32 = @intCast(cb.bytes.items.len);
        try cb.bytes.ensureUnusedCapacity(gpa, encoded_cert.len / 4 * 3 + 3);
        const dest_buf = cb.bytes.allocatedSlice()[decoded_start..];
        cb.bytes.items.len += try base64.decode(dest_buf, encoded_cert);
        try cb.parseCert(gpa, decoded_start, now_sec);
    }
}
