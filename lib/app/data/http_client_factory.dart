import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

bool isLoopbackAddress(Uri uri) {
  final host = uri.host.toLowerCase().replaceAll(RegExp(r'^\[|\]$'), '');
  return host == 'localhost' || (InternetAddress.tryParse(host)?.isLoopback ?? false);
}

String proxyForUri(Uri uri) => isLoopbackAddress(uri)
    ? 'DIRECT'
    : HttpClient.findProxyFromEnvironment(uri);

http.Client createAppHttpClient() => IOClient(HttpClient()..findProxy = proxyForUri);
