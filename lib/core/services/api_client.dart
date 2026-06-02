// API client — base HTTP wrapper (Dio) for backend v3.
import 'package:dio/dio.dart';

class ApiClient {
  ApiClient._internal();
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  // TODO: move to env/config later.
  static const String baseUrl = 'https://lora2u.com/v2/api';

  late final Dio dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
      // Don't throw on non-2xx — handle status manually.
      validateStatus: (status) => status != null && status < 500,
    ),
  );
}
