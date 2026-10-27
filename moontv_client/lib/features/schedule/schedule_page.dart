import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/bangumi_schedule.dart';
import '../../domain/models/media_item.dart';
import '../../providers.dart';
import '../../shared/widgets/error_view.dart';
import '../../shared/widgets/smart_image.dart';

final bangumiScheduleProvider = FutureProvider.autoDispose<BangumiSchedule>((ref) {
  return ref.watch(appDependenciesProvider).mediaRepository.bangumiSchedule();
});

class SchedulePage extends ConsumerStatefulWidget {
  const SchedulePage({super.key});

  @override
  ConsumerState<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends ConsumerState<SchedulePage> {
  var _selectedDay = 0; // 0 = 全部

  @override
  Widget build(BuildContext context) {
    final schedule = ref.watch(bangumiScheduleProvider);
    return schedule.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => ErrorView(
        message: '新番表加载失败：$error',
        onRetry: () => ref.invalidate(bangumiScheduleProvider),
      ),
      data: (data) {
        final days = data.days.where((day) => day.items.isNotEmpty).toList();
        if (days.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('新番表暂时为空'),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => ref.invalidate(bangumiScheduleProvider),
                  child: const Text('重新加载'),
                ),
              ],
            ),
          );
        }
        final index = _selectedDay.clamp(0, days.length);
        final visibleDays = index == 0 ? days : [days[index - 1]];
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('新番追更', style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 2),
                        Text(
                          data.year > 0
                              ? '${data.year} 年 ${data.seasonLabel} · 共 ${data.allItems.length} 部'
                              : '共 ${data.allItems.length} 部',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: '刷新',
                    onPressed: () => ref.invalidate(bangumiScheduleProvider),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: days.length + 1,
                separatorBuilder: (context, i) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final label = i == 0 ? '全部' : (days[i - 1].labelCn.isEmpty ? days[i - 1].labelEn : days[i - 1].labelCn);
                  return ChoiceChip(
                    label: Text(label),
                    selected: _selectedDay == i,
                    onSelected: (_) => setState(() => _selectedDay = i),
                  );
                },
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                itemCount: visibleDays.length,
                itemBuilder: (context, dayIndex) {
                  final day = visibleDays[dayIndex];
                  final label = day.labelCn.isEmpty ? day.labelEn : day.labelCn;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (index == 0)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 14, 4, 10),
                          child: Row(
                            children: [
                              Text(
                                label,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${day.items.length} 部',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      for (final item in day.items)
                        _BangumiTile(item: item),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BangumiTile extends StatelessWidget {
  const _BangumiTile({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.push('/search', extra: item.title),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 58,
                    height: 82,
                    child: item.poster.isEmpty
                        ? ColoredBox(color: scheme.surfaceContainerHighest)
                        : SmartImage(
                            url: item.poster,
                            fit: BoxFit.cover,
                            errorBuilder: (context) => ColoredBox(
                              color: scheme.surfaceContainerHighest,
                              child: const Icon(Icons.broken_image_outlined, size: 18),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (item.year.isNotEmpty)
                            Text(item.year, style: Theme.of(context).textTheme.bodySmall),
                          if (item.remarks.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.star_rounded, size: 14, color: scheme.tertiary),
                            Text(
                              item.remarks,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
