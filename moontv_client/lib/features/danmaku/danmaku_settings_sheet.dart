import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';

class DanmakuSettingsSheet extends ConsumerWidget {
  const DanmakuSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dependencies = ref.read(appDependenciesProvider);
    final settings = dependencies.settings.settings;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outline,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('弹幕设置', style: Theme.of(context).textTheme.titleLarge),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('启用弹幕'),
            value: settings.danmakuEnabled,
            onChanged: (value) => dependencies.settings.update(settings.copyWith(danmakuEnabled: value)),
          ),
          _SliderTile(
            title: '字号',
            value: settings.danmakuFontSize,
            min: 18,
            max: 40,
            label: '${settings.danmakuFontSize.round()}',
            onChanged: (value) => dependencies.settings.update(settings.copyWith(danmakuFontSize: value)),
          ),
          _SliderTile(
            title: '速度',
            value: settings.danmakuSpeed,
            min: 0.5,
            max: 2,
            label: '${settings.danmakuSpeed.toStringAsFixed(1)}x',
            onChanged: (value) => dependencies.settings.update(settings.copyWith(danmakuSpeed: value)),
          ),
          _SliderTile(
            title: '透明度',
            value: settings.danmakuOpacity,
            min: 0.2,
            max: 1,
            label: '${(settings.danmakuOpacity * 100).round()}%',
            onChanged: (value) => dependencies.settings.update(settings.copyWith(danmakuOpacity: value)),
          ),
          _SliderTile(
            title: '显示区域',
            value: settings.danmakuArea,
            min: 0.25,
            max: 1,
            label: '${(settings.danmakuArea * 100).round()}%',
            onChanged: (value) => dependencies.settings.update(settings.copyWith(danmakuArea: value)),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('来源上限'),
            subtitle: Text('最多自动聚合 ${settings.danmakuMaxSources} 个弹幕源'),
            trailing: DropdownButton<int>(
              value: settings.danmakuMaxSources,
              items: const [4, 8, 12, 16]
                  .map((value) => DropdownMenuItem(value: value, child: Text('$value')))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  dependencies.settings.update(settings.copyWith(danmakuMaxSources: value));
                }
              },
            ),
          ),
          TextFormField(
            initialValue: settings.blockedWords,
            decoration: const InputDecoration(
              labelText: '屏蔽词',
              hintText: '多个词用逗号分隔',
            ),
            onChanged: (value) => dependencies.settings.update(settings.copyWith(blockedWords: value)),
          ),
        ],
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.onChanged,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final String label;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Slider(value: value, min: min, max: max, onChanged: onChanged),
      trailing: Text(label),
    );
  }
}
