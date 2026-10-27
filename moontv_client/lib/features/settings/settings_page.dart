import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers.dart';
import '../../shared/widgets/glass_card.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dependencies = ref.read(appDependenciesProvider);
    final settings = dependencies.settings.settings;
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
                onChanged: (value) => dependencies.settings.update(settings.copyWith(autoplayNext: value)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('硬件解码优先'),
                subtitle: const Text('优先调用 GPU 硬件加速解码，异常时回退软解'),
                value: settings.hardwareDecode,
                onChanged: (value) => dependencies.settings.update(settings.copyWith(hardwareDecode: value)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('服务端去广告切片'),
                subtitle: const Text('经 /api/proxy-m3u8 剔除插播广告；服务器连不上片源时会自动改回直连'),
                value: settings.adblock,
                onChanged: (value) => dependencies.settings.update(settings.copyWith(adblock: value)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('代理 TS 分片'),
                subtitle: const Text('源站防盗链严格无法直连分片时开启（消耗服务端带宽）'),
                value: settings.proxySegments,
                onChanged: (value) => dependencies.settings.update(settings.copyWith(proxySegments: value)),
              ),
              TextFormField(
                initialValue: settings.playbackToken,
                decoration: const InputDecoration(
                  labelText: '播放代理令牌（可选）',
                  hintText: '对应服务端 NEXT_PUBLIC_PROXY_M3U8_TOKEN',
                ),
                onChanged: (value) => dependencies.settings.update(settings.copyWith(playbackToken: value.trim())),
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
                onChanged: (value) => dependencies.settings.update(settings.copyWith(danmakuEnabled: value)),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('字号'),
                subtitle: Slider(
                  min: 18,
                  max: 40,
                  value: settings.danmakuFontSize,
                  onChanged: (value) => dependencies.settings.update(settings.copyWith(danmakuFontSize: value)),
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
                  onChanged: (value) => dependencies.settings.update(settings.copyWith(danmakuOpacity: value)),
                ),
                trailing: Text('${(settings.danmakuOpacity * 100).round()}%'),
              ),
            ],
          ),
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
                onSelectionChanged: (value) => dependencies.settings.update(settings.copyWith(themeModeIndex: value.first)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('减弱动效'),
                value: settings.reduceMotion,
                onChanged: (value) => dependencies.settings.update(settings.copyWith(reduceMotion: value)),
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
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.info_outline),
                title: const Text('NEWTV · v0.1.0'),
                subtitle: const Text('MoonTVPlus 多端原生客户端（支持 Windows / Android / Android TV）'),
                trailing: TextButton(
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: 'NEWTV',
                    applicationVersion: '0.1.0',
                    applicationLegalese: '后端协议兼容：MoonTVPlus (CC BY-NC-SA 4.0)\n界面交互致谢：NipaPlay-Reload (MIT)',
                  ),
                  child: const Text('开源许可'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
