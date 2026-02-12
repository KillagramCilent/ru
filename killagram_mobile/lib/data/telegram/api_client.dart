import 'package:dio/dio.dart';
import '../../core/config/api_config.dart';
import 'api_exception.dart';
import 'auth_storage.dart';

class ApiClient {
  ApiClient(this._authStorage)
      : _dio = Dio(
          BaseOptions(
            baseUrl: ApiConfig.baseUrl,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 15),
          ),
        );

  final Dio _dio;
  final AuthStorage _authStorage;

  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authorized = false,
  }) async {
    final headers = await _buildHeaders(authorized);
    try {
      return await _dio.get(
        path,
        queryParameters: queryParameters,
        options: Options(headers: headers),
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<Response<dynamic>> post(
    String path, {
    Object? data,
    bool authorized = false,
  }) async {
    final headers = await _buildHeaders(authorized);
    try {
      return await _dio.post(
        path,
        data: data,
        options: Options(headers: headers),
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<Map<String, String>> _buildHeaders(bool authorized) async {
    if (!authorized) {
      return {};
    }
    final token = await _authStorage.readToken();
    final phone = await _authStorage.readPhone();
    if (token == null || phone == null) {
      throw ApiException('Необходимо повторно войти', statusCode: 401);
    }
    return {
      'Authorization': 'Bearer $token',
      'X-Phone': phone,
    };
  }

  ApiException _mapError(DioException error) {
    final status = error.response?.statusCode;
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return ApiException('Превышено время ожидания ответа.', statusCode: status);
    }
    if (error.type == DioExceptionType.connectionError) {
      return ApiException('Нет подключения к интернету.', statusCode: status);
    }
    if (status == 401) {
      return ApiException('Сессия истекла. Войдите снова.', statusCode: status);
    }
    if (status == 429) {
      return ApiException('Слишком много запросов. Попробуйте позже.', statusCode: status);
    }
    if (status != null && status >= 500) {
      return ApiException('Сервер временно недоступен.', statusCode: status);
    }
    return ApiException('Ошибка сети. Проверьте соединение.', statusCode: status);
  }
}
