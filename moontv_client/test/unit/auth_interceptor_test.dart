import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moontv_client/core/network/auth_interceptor.dart';
import 'package:moontv_client/data/api/endpoints.dart';

/// Deterministic in-memory adapter: the handler runs once per request,
/// unlike http_mock_adapter 0.6.x whose registration callback runs once.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  final Response<dynamic> Function(RequestOptions options) handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    requests.add(options);
    final response = handler(options);
    final data = jsonEncode(response.data);
    return ResponseBody.fromString(
      data,
      response.statusCode ?? 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  Dio createDio(FakeAdapter adapter, void Function() onExpired) {
    final dio = Dio(BaseOptions(baseUrl: 'https://server.example.com'));
    dio.httpClientAdapter = adapter;
    dio.interceptors.add(
      AuthInterceptor(dio, onSessionExpired: () async => onExpired()),
    );
    return dio;
  }

  test('three concurrent 401 responses share one refresh request', () async {
    var expiredCalls = 0;
    var refreshCalls = 0;
    var resourceCalls = 0;
    final adapter = FakeAdapter((options) {
      if (options.path == Endpoints.refresh) {
        refreshCalls++;
        return Response(requestOptions: options, statusCode: 200, data: {'ok': true});
      }
      resourceCalls++;
      final status = resourceCalls <= 3 ? 401 : 200;
      return Response(requestOptions: options, statusCode: status, data: {'ok': true});
    });
    final dio = createDio(adapter, () => expiredCalls++);

    final responses = await Future.wait([
      dio.get<dynamic>('/resource'),
      dio.get<dynamic>('/resource'),
      dio.get<dynamic>('/resource'),
    ]);

    expect(refreshCalls, 1);
    expect(resourceCalls, 6);
    expect(expiredCalls, 0);
    expect(responses.every((response) => response.statusCode == 200), isTrue);
  });

  test('the original request is replayed at most once', () async {
    var expiredCalls = 0;
    var refreshCalls = 0;
    var resourceCalls = 0;
    final adapter = FakeAdapter((options) {
      if (options.path == Endpoints.refresh) {
        refreshCalls++;
        return Response(requestOptions: options, statusCode: 200, data: {'ok': true});
      }
      resourceCalls++;
      return Response(requestOptions: options, statusCode: 401, data: {'message': 'still unauthorized'});
    });
    final dio = createDio(adapter, () => expiredCalls++);

    await expectLater(
      dio.get<dynamic>('/resource'),
      throwsA(
        isA<DioException>().having(
          (error) => error.response?.statusCode,
          'statusCode',
          401,
        ),
      ),
    );
    expect(refreshCalls, 1);
    expect(resourceCalls, 2);
    expect(expiredCalls, 0);
  });

  test('failed refresh expires the local session without replay', () async {
    var expiredCalls = 0;
    var refreshCalls = 0;
    var resourceCalls = 0;
    final adapter = FakeAdapter((options) {
      if (options.path == Endpoints.refresh) {
        refreshCalls++;
        return Response(requestOptions: options, statusCode: 401, data: {'message': 'refresh expired'});
      }
      resourceCalls++;
      return Response(requestOptions: options, statusCode: 401, data: {'message': 'Access token expired'});
    });
    final dio = createDio(adapter, () => expiredCalls++);

    await expectLater(
      dio.get<dynamic>('/resource'),
      throwsA(isA<DioException>()),
    );
    expect(refreshCalls, 1);
    expect(resourceCalls, 1);
    expect(expiredCalls, 1);
  });

  test('a replay marked as retried is not refreshed again', () async {
    var refreshCalls = 0;
    final adapter = FakeAdapter((options) {
      if (options.path == Endpoints.refresh) {
        refreshCalls++;
        return Response(requestOptions: options, statusCode: 200, data: {'ok': true});
      }
      // The interceptor replays with extra['newtvRetried'] == true; a second
      // 401 on the replay must propagate without another refresh round.
      final isReplay = options.extra['newtvRetried'] == true;
      return Response(
        requestOptions: options,
        statusCode: 401,
        data: {'message': isReplay ? 'replay rejected' : 'Access token expired'},
      );
    });
    var expiredCalls = 0;
    final dio = createDio(adapter, () => expiredCalls++);

    await expectLater(
      dio.get<dynamic>('/resource'),
      throwsA(isA<DioException>()),
    );
    expect(refreshCalls, 1);
    expect(expiredCalls, 0);
  });
}
