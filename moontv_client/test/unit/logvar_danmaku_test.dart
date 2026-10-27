import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moontv_client/data/api/danmaku_api.dart';
import 'package:moontv_client/domain/models/danmaku.dart';

void main() {
  group('parseLogVarComments', () {
    test('4 段 p（时间,模式,颜色,池）按 LogVar 变体解析', () {
      final comments = parseLogVarComments({
        'errorCode': 0,
        'count': 2,
        'comments': [
          {'cid': 1622, 'p': '0.04,1,15138834,[bilibili1]', 'm': '二刷来了！', 't': 0.04},
          {'cid': 4, 'p': '5.24,5,16777215,[bilibili1]', 'm': '好耶', 't': 0.71},
        ],
      }, source: 'bilibili');
      expect(comments.length, 2);
      final first = comments.first;
      expect(first.time, 0.04);
      expect(first.mode, DanmakuMode.scroll);
      // 颜色必须是第三段，而不是被当成字号。
      expect(first.color, 15138834);
      expect(first.fontSize, 25);
      expect(first.pool, '[bilibili1]');
      expect(first.id, '1622');
      expect(first.text, '二刷来了！');
      expect(first.source, 'bilibili');
      expect(comments[1].mode, DanmakuMode.top);
    });

    test('标准 dandanplay 8 段 p 仍按字号/颜色位置解析', () {
      final comments = parseLogVarComments({
        'comments': [
          {'p': '12.5,4,25,65280,1700000000,pool,userhash,row1', 'm': '底部弹幕'},
        ],
      }, source: 'dandan');
      expect(comments.single.mode, DanmakuMode.bottom);
      expect(comments.single.fontSize, 25);
      expect(comments.single.color, 65280);
      expect(comments.single.userHash, 'userhash');
    });

    test('空文本与非法结构被跳过', () {
      final comments = parseLogVarComments({
        'comments': [
          {'p': '1,1,16777215,pool', 'm': '   '},
          {'p': '2,1,16777215,pool'},
          'not-a-map',
        ],
      }, source: 'x');
      expect(comments, isEmpty);
    });

    test('响应不是 map 时返回空列表', () {
      expect(parseLogVarComments(null, source: 'x'), isEmpty);
      expect(parseLogVarComments('oops', source: 'x'), isEmpty);
      expect(parseLogVarComments({'comments': 'oops'}, source: 'x'), isEmpty);
    });

    test('缺少 cid 时回退到 p 的第 8 段作为 id', () {
      final comments = parseLogVarComments({
        'comments': [
          {'p': '3,1,25,16777215,0,pool,user,row9', 'm': 'hi'},
        ],
      }, source: 'x');
      expect(comments.single.id, 'row9');
    });
  });

  group('LogVarDanmakuApi 端点约定', () {
    test('非聚合数据源：跳过客户端多源合并', () {
      final api = LogVarDanmakuApi(Dio(), 'http://127.0.0.1:9321/token');
      expect(api.aggregates, isFalse);
    });
  });
}
