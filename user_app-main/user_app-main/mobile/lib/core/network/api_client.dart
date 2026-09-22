import 'package:dio/dio.dart';
import '../storage/secure_storage.dart';
import '../utils/app_constants.dart';

class ApiClient {
  static final Dio _dio = Dio(BaseOptions(
    baseUrl: AppConstants.apiUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    headers: {'Content-Type': 'application/json'},
  ));

  static bool _interceptorSetup = false;

  static Dio get instance {
    if (!_interceptorSetup) {
      _setupInterceptors();
      _interceptorSetup = true;
    }
    return _dio;
  }

  static void _setupInterceptors() {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        print('[MOCK API] Intercepted Request: ${options.method} ${options.path}');
        
        await Future.delayed(const Duration(milliseconds: 500)); // Simulate network latency

        if (options.path.contains('/auth/login') || options.path.contains('/auth/register')) {
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'status': 'success',
              'data': {
                'user': {
                  'id': 'mock-user-id',
                  'name': 'Demo User',
                  'email': 'demo@example.com',
                  'phone': '1234567890',
                  'role': 'USER',
                  'createdAt': DateTime.now().toIso8601String(),
                },
                'accessToken': 'mock-access-token',
                'refreshToken': 'mock-refresh-token',
              }
            }
          ));
        }

        if (options.path.contains('/users/me')) {
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'status': 'success',
              'data': {
                'id': 'mock-user-id',
                'name': 'Demo User',
                'email': 'demo@example.com',
                'phone': '1234567890',
                'role': 'USER',
                'createdAt': DateTime.now().toIso8601String(),
              }
            }
          ));
        }

        if (options.path.contains('/bookings')) {
          if (options.method == 'GET') {
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'status': 'success',
                'data': {
                  'bookings': [],
                  'pagination': {
                    'page': 1,
                    'pages': 1,
                    'total': 0,
                  }
                }
              }
            ));
          } else if (options.method == 'POST') {
             return handler.resolve(Response(
              requestOptions: options,
              statusCode: 201,
              data: {
                'status': 'success',
                'data': {
                  'id': 'mock-booking-id',
                  'userId': 'mock-user-id',
                  'type': options.data['type'] ?? 'IMMEDIATE',
                  'status': 'PENDING',
                  'addressLine': options.data['addressLine'] ?? '',
                  'latitude': options.data['latitude'] ?? 0.0,
                  'longitude': options.data['longitude'] ?? 0.0,
                  'wasteType': options.data['wasteType'] ?? 'general',
                  'quantity': options.data['quantity'] ?? 'small',
                  'createdAt': DateTime.now().toIso8601String(),
                }
              }
            ));
          } else if (options.method == 'PATCH') { // For cancel
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'status': 'success',
                'data': {}
              }
            ));
          }
        }

        if (options.path.contains('/auth/logout')) {
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {'status': 'success'}
          ));
        }

        if (options.path.contains('/payments/create-order')) {
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'status': 'success',
              'data': {
                'orderId': 'mock-order-id',
              }
            }
          ));
        }

        if (options.path.contains('/payments/verify')) {
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'status': 'success',
              'data': {}
            }
          ));
        }

        if (options.path.contains('/ratings')) {
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'status': 'success',
              'data': {}
            }
          ));
        }

        // Fallback for unmocked routes
        return handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: {'status': 'success', 'data': {}}
        ));
      },
    ));
  }

  static String getErrorMessage(dynamic error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] != null) {
        return data['message'] as String;
      }
      if (error.type == DioExceptionType.connectionTimeout) {
        return 'Connection timeout. Check your internet.';
      }
      if (error.type == DioExceptionType.connectionError) {
        return 'Cannot reach server. Check your connection.';
      }
    }
    return 'Something went wrong. Please try again.';
  }
}
