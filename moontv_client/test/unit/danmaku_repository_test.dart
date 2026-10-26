import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moontv_client/data/api/danmaku_api.dart';
import 'package:moontv_client/data/repositories/danmaku_repository.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final Map<String, dynamic> Function(String path, Map<String, String> query) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    final query = options.queryParameters.map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );
    final body = handler(options.path, query);
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

DanmakuRepository _repo(
  _FakeAdapter adapter, {
  DanmakuCache? cache,
}) =>
    DanmakuRepository(
      DanmakuApi(Dio(BaseOptions())..httpClientAdapter = adapter),
      cache: cache,
    );

Map<String, dynamic> _animes() => {
      'animes': [
        {'animeId': 'a1', 'animeTitle': '葬送的芙莉莲', 'type': 'tvseries', 'typeDescription': ''},
        {'animeId': 'a2', 'animeTitle': '葬送的芙莉莲（B站源）', 'type': 'tvseries', 'typeDescription': ''},
      ],
    };

Map<String, dynamic> _episodes(int count) => {
      'bangumi': {
        'episodes': List<Map<String, dynamic>>.generate(
          count,
          (index) => {
            'episodeId': 'ep${index + 1}',
            'episodeTitle': '第${index + 1}集',
          },
        ),
      },
    };

Map<String, dynamic> _comments(List<String> texts) => {
      'comments': texts
          .map(
            (text) => {
              'p': '1.0,1,25,16777215,1700000000,0,hash,0',
              'm': text,
            },
          )
          .toList(),
    };

void main() {
  test('aggregates comments across every matched source', () async {
    final adapter = _FakeAdapter((path, query) {
      if (path.contains('search')) return _animes();
      if (path.contains('episodes')) return _episodes(12);
      if (path.contains('comment')) {
        // Both sources return the same timeline; merger must dedupe overlap.
        return _comments(['你好', '世界']);
      }
      return const {};
    });
    final result = await _repo(adapter).load(
      title: '葬送的芙莉莲',
      episodeNumber: 3,
      totalEpisodes: 12,
    );

    expect(result.fromCache, isFalse);
    expect(result.totalSources, 2);
    expect(result.loadedSources, 2);
    // Same-timestamp comments have no order guarantee across sources.
    expect(result.comments.map((e) => e.text).toSet(), {'你好', '世界'});
    expect(result.comments.every((e) => e.time == 1.0), isTrue);
  });

  test('uses the cache on a second load and skips the network', () async {
    var searchCalls = 0;
    final adapter = _FakeAdapter((path, query) {
      if (path.contains('search')) {
        searchCalls++;
        return _animes();
      }
      if (path.contains('episodes')) return _episodes(12);
      if (path.contains('comment')) return _comments(['cached']);
      return const {};
    });
    final repository = _repo(adapter, cache: MemoryDanmakuCache());

    final first = await repository.load(title: '葬送的芙莉莲', episodeNumber: 1, totalEpisodes: 12);
    final second = await repository.load(title: '葬送的芙莉莲', episodeNumber: 1, totalEpisodes: 12);

    expect(first.fromCache, isFalse);
    expect(second.fromCache, isTrue);
    expect(second.comments.map((e) => e.text), ['cached']);
    expect(searchCalls, 1);
  });

  test('reports a clean failure when no source matches the episode', () async {
    final adapter = _FakeAdapter((path, query) {
      if (path.contains('search')) return _animes();
      if (path.contains('episodes')) return _episodes(2);
      return const {};
    });
    final result = await _repo(adapter).load(title: '葬送的芙莉莲', episodeNumber: 9);

    expect(result.comments, isEmpty);
    expect(result.loadedSources, 0);
    expect(result.message, isNotEmpty);
  });
}
