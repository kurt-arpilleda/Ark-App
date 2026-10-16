import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:fluttertoast/fluttertoast.dart';

class ApiService {
  static const List<String> apiUrls = [
    "https://113.19.11.218/",
    "https://192.168.254.163/"
  ];

  static const Duration requestTimeout = Duration(seconds: 2);
  static const int maxRetries = 6;
  static const Duration initialRetryDelay = Duration(seconds: 1);

  int? _lastWorkingServerIndex;
  late http.Client httpClient;

  ApiService() {
    httpClient = _createHttpClient();
  }

  http.Client _createHttpClient() {
    final HttpClient client = HttpClient()
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    return IOClient(client);
  }

  void _showToast(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_LONG,
      gravity: ToastGravity.BOTTOM,
    );
  }

  Future<T> _makeParallelRequest<T>(Future<_ApiResult<T>> Function(String apiUrl) requestFn) async {
    if (_lastWorkingServerIndex != null) {
      try {
        return (await requestFn(apiUrls[_lastWorkingServerIndex!]).timeout(requestTimeout)).value;
      } catch (_) {
      }
    }

    final List<Future<_ApiResult<T>?>> futures = apiUrls.map((apiUrl) async {
      try {
        final result = await requestFn(apiUrl).timeout(requestTimeout);
        return result;
      } catch (e) {
        return null;
      }
    }).toList();

    final results = await Future.wait(futures);

    for (final result in results) {
      if (result != null) {
        _lastWorkingServerIndex = apiUrls.indexOf(result.apiUrlUsed);
        return result.value;
      }
    }

    throw Exception("All API URLs are unreachable");
  }

  Future<String> fetchSoftwareLink(int linkID) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _makeParallelRequest((apiUrl) async {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLinkAPI/kurt_fetchLink.php?linkID=$linkID");
          print("Trying: $uri");
          final response = await httpClient.get(uri);

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data.containsKey("softwareLink")) {
              String relativePath = data["softwareLink"];
              String fullUrl = Uri.parse(apiUrl).resolve(relativePath).toString();
              return _ApiResult(fullUrl, apiUrl);
            } else {
              throw Exception(data["error"] ?? "Invalid response format");
            }
          }
          throw Exception("HTTP ${response.statusCode}");
        });

        return result;
      } catch (e) {
        print("Attempt $attempt failed: $e");
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1));
          print("Waiting ${delay.inSeconds} seconds before retry...");
          await Future.delayed(delay);
        }
      }
    }

    String finalError = "All API URLs are unreachable after $maxRetries attempts";
    _showToast(finalError);
    throw Exception(finalError);
  }

  static void setupHttpOverrides() {
    HttpOverrides.global = MyHttpOverrides();
  }
}

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

class _ApiResult<T> {
  final T value;
  final String apiUrlUsed;

  _ApiResult(this.value, this.apiUrlUsed);
}