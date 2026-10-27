import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/config/app_settings.dart';
import '../../core/network/api_exception.dart';
import '../../data/api/danmaku_api.dart';
import '../../providers.dart';
import '../../shared/widgets/glass_card.dart';

/// 版本号取一次就缓存，避免每次 rebuild 都走平台通道。
final _appInfoFuture = PackageInfo.fromPlatform();

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dependencies = ref.read(appDependenciesProvider);
    // watch：改任一开关后本页立即刷新（此前 read 快照导致要重进页面）。
    final storage = ref.watch(settingsProvider);
    final settings = storage.settings;
    void update(AppSettings Function(AppSettings current) change) =>
        storage.update(change(settings));

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('服务器', style: Theme.of(context).textTheme.titleMedium),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.dns_outlined),
                title: Text(dependencies.session.server?.baseUrl ?? '未配置'),
                subtitle: dependencies.session.server?.isSecure == false
                    ? const Text('非加密连接', style: TextStyle(color: Colors.orange))
                    : null,
                trailing: TextButton(
                  onPressed: () => context.push('/onboarding'),
                  child: const Text('修改'),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () async {
                  await dependencies.authApi.logout();
                  await dependencies.session.clearSession();
                  if (context.mounted) context.go('/login');
                },
                icon: const Icon(Icons.logout),
                label: const Text('退出登录'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('播放', style: Theme.of(context).textTheme.titleMedium),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('自动连播下一集'),
                subtitle: const Text('当前剧集播放结束后自动无缝切换下一集'),
                value: settings.autoplayNext,
                onChanged: (value) =>
                    update((current) => current.copyWith(autoplayNext: value)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('硬件解码优先'),
                subtitle: const Text('优先调用 GPU 硬件加速解码，异常时回退软解'),
                value: settings.hardwareDecode,
                onChanged: (value) =>
                    update((current) => current.copyWith(hardwareDecode: value)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('服务端去广告切片'),
                subtitle: const Text('经 /api/proxy-m3u8 剔除插播广告；服务器连不上片源时会自动改回直连'),
                value: settings.adblock,
                onChanged: (value) =>
                    update((current) => current.copyWith(adblock: value)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('代理 TS 分片'),
                subtitle: const Text('源站防盗链严格无法直连分片时开启（消耗服务端带宽）'),
                value: settings.proxySegments,
                onChanged: (value) =>
                    update((current) => current.copyWith(proxySegments: value)),
              ),
              TextFormField(
                initialValue: settings.playbackToken,
                decoration: const InputDecoration(
                  labelText: '播放代理令牌（可选）',
                  hintText: '对应服务端 NEXT_PUBLIC_PROXY_M3U8_TOKEN',
                ),
                onChanged: (value) =>
                    update((current) => current.copyWith(playbackToken: value.trim())),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('沉浸模式保留迷你进度条'),
                subtitle: const Text('控制栏隐藏后，底部保留一条 2px 进度细线'),
                value: settings.immersiveMiniProgress,
                onChanged: (value) => update(
                  (current) => current.copyWith(immersiveMiniProgress: value),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('弹幕', style: Theme.of(context).textTheme.titleMedium),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('自动加载弹幕'),
                subtitle: const Text('进入播放页后自动搜索、匹配并合并所有可用来源'),
                value: settings.danmakuEnabled,
                onChanged: (value) =>
                    update((current) => current.copyWith(danmakuEnabled: value)),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('字号'),
                subtitle: Slider(
                  min: 18,
                  max: 40,
                  value: settings.danmakuFontSize,
                  onChanged: (value) =>
                      update((current) => current.copyWith(danmakuFontSize: value)),
                ),
                trailing: Text('${settings.danmakuFontSize.round()}'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('透明度'),
                subtitle: Slider(
                  min: 0.2,
                  max: 1,
                  value: settings.danmakuOpacity,
                  onChanged: (value) =>
                      update((current) => current.copyWith(danmakuOpacity: value)),
                ),
                trailing: Text('${(settings.danmakuOpacity * 100).round()}%'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _DanmakuServiceCard(
          settings: settings,
          onModeChanged: (mode) =>
              update((current) => current.copyWith(danmakuApiMode: mode)),
          onBaseUrlChanged: (url) =>
              update((current) => current.copyWith(danmakuApiBaseUrl: url)),
        ),
        const SizedBox(height: 16),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('外观', style: Theme.of(context).textTheme.titleMedium),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('跟随系统')),
                  ButtonSegment(value: 1, label: Text('亮色')),
                  ButtonSegment(value: 2, label: Text('暗色')),
                ],
                selected: {settings.themeModeIndex},
                onSelectionChanged: (value) =>
                    update((current) => current.copyWith(themeModeIndex: value.first)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('减弱动效'),
                value: settings.reduceMotion,
                onChanged: (value) =>
                    update((current) => current.copyWith(reduceMotion: value)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('关于', style: Theme.of(context).textTheme.titleMedium),
              FutureBuilder<PackageInfo>(
                future: _appInfoFuture,
                builder: (context, snapshot) {
                  final info = snapshot.data;
                  final version = info == null
                      ? '—'
                      : 'v${info.version}+${info.buildNumber}';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.info_outline),
                    title: Text('NEWTV · $version'),
                    subtitle: const Text('MoonTVPlus 多端原生客户端（支持 Windows / Android / Android TV）'),
                    trailing: TextButton(
                      onPressed: () => showLicensePage(
                        context: context,
                        applicationName: 'NEWTV',
                        applicationVersion: info?.version ?? '',
                        applicationLegalese:
                            '后端协议兼容：MoonTVPlus (CC BY-NC-SA 4.0)\n界面交互致谢：NipaPlay-Reload (MIT)',
                      ),
                      child: const Text('开源许可'),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 弹幕服务切换：后端链路 / 自建 LogVar API，含连通性测试。
class _DanmakuServiceCard extends ConsumerStatefulWidget {
  const _DanmakuServiceCard({
    required this.settings,
    required this.onModeChanged,
    required this.onBaseUrlChanged,
  });

  final AppSettings settings;
  final ValueChanged<int> onModeChanged;
  final ValueChanged<String> onBaseUrlChanged;

  @override
  ConsumerState<_DanmakuServiceCard> createState() => _DanmakuServiceCardState();
}

class _DanmakuServiceCardState extends ConsumerState<_DanmakuServiceCard> {
  late final TextEditingController _controller;
  var _testing = false;
  String? _result;
  var _resultOk = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.settings.danmakuApiBaseUrl);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    final url = _controller.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _testing = true;
      _result = null;
    });
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        headers: const {'Accept': 'application/json'},
      ),
    );
    try {
      await testLogVarConnection(dio, url);
      if (!mounted) return;
      setState(() {
        _testing = false;
        _resultOk = true;
        _result = '连接正常，弹幕服务可用';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _resultOk = false;
        _result = readableError(error);
      });
    } finally {
      dio.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final custom = widget.settings.useCustomDanmakuApi;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('弹幕服务', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '自建弹幕 API 已聚合多源，选择后不再做客户端多源合并',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('后端')),
              ButtonSegment(value: 1, label: Text('自定义')),
            ],
            selected: {widget.settings.danmakuApiMode},
            onSelectionChanged: (value) => widget.onModeChanged(value.first),
          ),
          if (custom) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: '弹幕 API 地址',
                hintText: 'http://host:9321/87654321',
                helperText: '路径令牌即鉴权，填到令牌为止',
              ),
              onChanged: widget.onBaseUrlChanged,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _testing ? null : _test,
                  icon: _testing
                      ? const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering, size: 18),
                  label: const Text('测试连通'),
                ),
                const SizedBox(width: 12),
                if (_result != null)
                  Expanded(
                    child: Text(
                      _result!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _resultOk ? theme.colorScheme.primary : theme.colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
