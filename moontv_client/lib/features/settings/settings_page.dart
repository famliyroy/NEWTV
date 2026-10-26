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
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.info_outline),
                title: Text('NEWTV'),
                subtitle: Text('MoonTVPlus 原生客户端 · 含 MoonTVPlus CC BY-NC-SA 4.0 与 NipaPlay-Reload MIT 声明'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
