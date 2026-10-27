import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_settings.dart';
import '../../providers.dart';
import 'danmaku_controller.dart';

/// 弹幕设置面板。
///
/// 面板内容比一屏高（横屏播放时尤其明显），因此外层用
/// `DraggableScrollableSheet`：滚动内容到顶后继续下拉会让面板收缩，
/// 收到最小高度时关闭；拖把手/空白处则走 BottomSheet 自带的拖拽。
class DanmakuSettingsSheet extends ConsumerWidget {
  const DanmakuSettingsSheet({
    this.controller,
    this.scrollController,
    super.key,
  });

  /// 当前播放页的弹幕控制器：用于展示「当前弹幕源」，可为空。
  final DanmakuController? controller;

  /// 由 [DraggableScrollableSheet] 注入，交给内部 ListView。
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 必须 watch：设置是 ChangeNotifier，read 拿到的是一次性快照，
    // 拖滑块时连自己的 UI 都不会刷新。
    final storage = ref.watch(settingsProvider);
    final settings = storage.settings;
    void update(AppSettings Function(AppSettings current) change) =>
        storage.update(change(storage.settings));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SheetHeader(onDone: () => Navigator.of(context).maybePop()),
        Flexible(
          child: ListView(
            controller: scrollController,
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              _DanmakuSourceCard(controller: controller, settings: settings),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用弹幕'),
                value: settings.danmakuEnabled,
                onChanged: (value) =>
                    update((current) => current.copyWith(danmakuEnabled: value)),
              ),
              _SliderTile(
                title: '字号',
                value: settings.danmakuFontSize,
                min: 18,
                max: 40,
                labelBuilder: (value) => '${value.round()}',
                onCommit: (value) => update(
                  (current) => current.copyWith(danmakuFontSize: value),
                ),
              ),
              _SliderTile(
                title: '速度',
                value: settings.danmakuSpeed,
                min: 0.5,
                max: 2,
                labelBuilder: (value) => '${value.toStringAsFixed(1)}x',
                onCommit: (value) => update(
                  (current) => current.copyWith(danmakuSpeed: value),
                ),
              ),
              _SliderTile(
                title: '透明度',
                value: settings.danmakuOpacity,
                min: 0.2,
                max: 1,
                labelBuilder: (value) => '${(value * 100).round()}%',
                onCommit: (value) => update(
                  (current) => current.copyWith(danmakuOpacity: value),
                ),
              ),
              _SliderTile(
                title: '显示区域',
                value: settings.danmakuArea,
                min: 0.25,
                max: 1,
                labelBuilder: (value) => '${(value * 100).round()}%',
                onCommit: (value) => update(
                  (current) => current.copyWith(danmakuArea: value),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('来源上限'),
                subtitle: Text(
                  '最多自动聚合 ${settings.danmakuMaxSources} 个弹幕源（修改后自动重新加载）',
                ),
                trailing: DropdownButton<int>(
                  value: settings.danmakuMaxSources,
                  items: const [4, 8, 12, 16]
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text('$value')),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      update(
                        (current) => current.copyWith(danmakuMaxSources: value),
                      );
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
                onChanged: (value) =>
                    update((current) => current.copyWith(blockedWords: value)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 顶部固定区：拖拽把手 + 标题 + 完成按钮。
///
/// 把手区域不参与滚动，竖直拖拽会交给 BottomSheet 自带手势直接下拉关闭；
/// 「完成」按钮用于遥控器/鼠标等不方便做手势的场景。
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Container(
          width: 42,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.outline,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '弹幕设置',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              TextButton(onPressed: onDone, child: const Text('完成')),
            ],
          ),
        ),
      ],
    );
  }
}

/// 展示当前弹幕数据源、命中的作品与加载情况。
class _DanmakuSourceCard extends StatelessWidget {
  const _DanmakuSourceCard({required this.controller, required this.settings});

  final DanmakuController? controller;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: colors.onSurfaceVariant,
        );
    final valueStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        );
    final controller = this.controller;
    final provider = controller != null && controller.sourceDescription.isNotEmpty
        ? controller.sourceDescription
        : (settings.useCustomDanmakuApi ? '自定义 LogVar' : 'MoonTVPlus 聚合');

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: controller == null
          ? _content(
              context,
              provider: provider,
              matched: '',
              episode: '',
              from: '',
              status: '未接入播放页，无法读取加载状态',
              valueStyle: valueStyle,
              labelStyle: labelStyle,
            )
          : AnimatedBuilder(
              animation: controller,
              builder: (context, child) {
                final total = controller.comments.length;
                final status = controller.loading
                    ? '正在加载弹幕…'
                    : total > 0
                        ? '已加载 ${controller.loadedSources}/${controller.totalSources} 源 · 共 $total 条'
                        : '暂无弹幕';
                return _content(
                  context,
                  provider: provider,
                  matched: controller.matchedTitle,
                  episode: controller.matchedEpisode,
                  from: controller.providerName,
                  status: status,
                  valueStyle: valueStyle,
                  labelStyle: labelStyle,
                );
              },
            ),
    );
  }

  Widget _content(
    BuildContext context, {
    required String provider,
    required String matched,
    required String episode,
    required String from,
    required String status,
    required TextStyle? valueStyle,
    required TextStyle? labelStyle,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.source_outlined, size: 16, color: colors.primary),
            const SizedBox(width: 6),
            Text('当前弹幕源', style: labelStyle),
          ],
        ),
        const SizedBox(height: 8),
        Text(provider, style: valueStyle),
        if (matched.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            episode.isEmpty ? matched : '$matched · $episode',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (from.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text('提供方：$from', style: labelStyle),
        ],
        const SizedBox(height: 6),
        Text(status, style: labelStyle),
      ],
    );
  }
}

/// 滑块只在本地回显，松手（onChangeEnd）才写回设置。
///
/// 拖动过程中连续提交会让设置变更 → 弹幕图形缓存反复作废，表现为掉帧。
class _SliderTile extends StatefulWidget {
  const _SliderTile({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.labelBuilder,
    required this.onCommit,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final String Function(double value) labelBuilder;
  final ValueChanged<double> onCommit;

  @override
  State<_SliderTile> createState() => _SliderTileState();
}

class _SliderTileState extends State<_SliderTile> {
  double? _draft;

  @override
  Widget build(BuildContext context) {
    final value = _draft ?? widget.value;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(widget.title),
      subtitle: Slider(
        value: value.clamp(widget.min, widget.max),
        min: widget.min,
        max: widget.max,
        onChanged: (next) => setState(() => _draft = next),
        onChangeEnd: (next) {
          setState(() => _draft = null);
          widget.onCommit(next);
        },
      ),
      trailing: Text(widget.labelBuilder(value)),
    );
  }
}
