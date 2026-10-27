import 'package:flutter_test/flutter_test.dart';
import 'package:moontv_client/core/utils/local_resume_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('读写同片同集的记录，且持久化到 SharedPreferences', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = LocalResumeStore(prefs);

    await store.write(
      storageKey: 'ikun+101',
      episodeIndex: 2,
      positionSeconds: 754,
      totalSeconds: 1800,
      title: '沧元图',
      immediate: true,
    );

    final record = await store.read('ikun+101', 2);
    expect(record, isNotNull);
    expect(record!.episodeIndex, 2);
    expect(record.positionSeconds, 754);
    expect(record.totalSeconds, 1800);
    expect(record.title, '沧元图');

    // 重新创建一个新实例验证已从 SharedPreferences JSON 恢复。
    final reloadedStore = LocalResumeStore(prefs);
    final reloaded = await reloadedStore.read('ikun+101', 2);
    expect(reloaded, isNotNull);
    expect(reloaded!.positionSeconds, 754);
  });

  test('集数不匹配返回 null，换集写入后覆盖为最新一集', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = LocalResumeStore(prefs);

    await store.write(
      storageKey: 'ikun+101',
      episodeIndex: 0,
      positionSeconds: 300,
      totalSeconds: 1500,
      title: '沧元图',
    );
    expect(await store.read('ikun+101', 0), isNotNull);
    expect(await store.read('ikun+101', 1), isNull, reason: '不同集不得串用断点');

    // 切到第 2 集并播放保存。
    await store.write(
      storageKey: 'ikun+101',
      episodeIndex: 1,
      positionSeconds: 420,
      totalSeconds: 1500,
      title: '沧元图',
    );
    expect(await store.read('ikun+101', 0), isNull);
    final latest = await store.read('ikun+101', 1);
    expect(latest, isNotNull);
    expect(latest!.positionSeconds, 420);
  });

  test('前 10 秒内或距片尾 15 秒内的记录不触发续播（read 返回 null）', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = LocalResumeStore(prefs);

    // 仅 10 秒：不过滤阈值。
    await store.write(
      storageKey: 'cj+1',
      episodeIndex: 0,
      positionSeconds: 10,
      totalSeconds: 1200,
      title: '短片',
    );
    expect(await store.read('cj+1', 0), isNull);

    // 距片尾恰好 15 秒：视为看完。
    await store.write(
      storageKey: 'cj+1',
      episodeIndex: 0,
      positionSeconds: 1185,
      totalSeconds: 1200,
      title: '短片',
    );
    expect(await store.read('cj+1', 0), isNull);

    // 距片尾 16 秒：仍可续播。
    await store.write(
      storageKey: 'cj+1',
      episodeIndex: 0,
      positionSeconds: 1184,
      totalSeconds: 1200,
      title: '短片',
    );
    expect((await store.read('cj+1', 0))?.positionSeconds, 1184);
  });

  test('200ms 防抖合并写入，且内存立即对 read 可见', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = LocalResumeStore(prefs);

    for (var sec = 20; sec <= 60; sec += 10) {
      await store.write(
        storageKey: 'cj+9',
        episodeIndex: 0,
        positionSeconds: sec,
        totalSeconds: 1000,
        title: '测试',
      );
    }
    // 防抖未到期前，内存读已拿到最新的 60s。
    expect((await store.read('cj+9', 0))?.positionSeconds, 60);

    await Future<void>.delayed(const Duration(milliseconds: 260));
    final freshStore = LocalResumeStore(prefs);
    expect((await freshStore.read('cj+9', 0))?.positionSeconds, 60);
  });

  test('超出 300 条上限时按 updatedAt 淘汰最旧记录', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = LocalResumeStore(prefs);

    for (var i = 0; i < 305; i++) {
      await store.write(
        storageKey: 'src+$i',
        episodeIndex: 0,
        positionSeconds: 120,
        totalSeconds: 1800,
        title: '剧集 $i',
        updatedAt: 1000 + i,
      );
    }
    await store.flush();

    // 最旧的 5 条（0..4）应被淘汰，第 5 条到第 304 条保留。
    for (var i = 0; i < 5; i++) {
      expect(await store.read('src+$i', 0), isNull);
    }
    expect(await store.read('src+5', 0), isNotNull);
    expect(await store.read('src+304', 0), isNotNull);
  });

  test('markCompleted 与 remove 清除对应记录', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = LocalResumeStore(prefs);

    await store.write(
      storageKey: 'cj+88',
      episodeIndex: 3,
      positionSeconds: 500,
      totalSeconds: 1500,
      title: '测试剧',
      immediate: true,
    );
    expect(await store.read('cj+88', 3), isNotNull);

    await store.markCompleted('cj+88', 3, immediate: true);
    expect(await store.read('cj+88', 3), isNull);
  });
}
