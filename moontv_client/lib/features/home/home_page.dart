import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/media_item.dart';
import '../../providers.dart';
import '../../shared/widgets/empty_view.dart';
import '../../shared/widgets/error_view.dart';
import '../../shared/widgets/poster_card.dart';
import '../../shared/widgets/section_header.dart';

typedef HomeData = ({
  List<MediaItem> history,
  List<MediaItem> recommendations,
  List<MediaItem> bangumi,
  List<MediaItem> trending,
});

final homeDataProvider = FutureProvider.autoDispose<HomeData>((ref) async {
  final repository = ref.read(appDependenciesProvider).mediaRepository;
  Future<List<MediaItem>> safe(Future<List<MediaItem>> future) =>
      future.catchError((_) => <MediaItem>[]);
  final results = await Future.wait([
    safe(repository.history()),
    safe(repository.discoverFeed('movie')),
    safe(repository.trending()),
  ]);
  var today = <MediaItem>[];
  try {
    final schedule = await repository.bangumiSchedule();
    final days = schedule.days.where((day) => day.items.isNotEmpty).toList();
    if (days.isNotEmpty) {
      final index = (DateTime.now().weekday - 1).clamp(0, days.length - 1);
      today = days[index].items;
    }
  } on Object {
    today = <MediaItem>[];
  }
  return (
    history: results[0],
    recommendations: results[1],
    bangumi: today,
    trending: results[2],
  );
});

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(homeDataProvider);
    return data.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => ErrorView(
        message: error.toString(),
        onRetry: () => ref.invalidate(homeDataProvider),
      ),
      data: (data) {
        if (data.history.isEmpty &&
            data.recommendations.isEmpty &&
            data.bangumi.isEmpty &&
            data.trending.isEmpty) {
          return EmptyView(
            title: '开始你的第一部作品',
            message: '从发现页或搜索页查找电影、剧集或番剧',
            actionLabel: '去发现',
            onAction: () => context.go('/discover'),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
          children: [
            if (data.history.isNotEmpty) ...[
              const SectionHeader(title: '继续观看'),
              _MediaRail(items: data.history),
              const SizedBox(height: 28),
            ],
            if (data.bangumi.isNotEmpty) ...[
              const SectionHeader(title: '今日更新'),
              _MediaRail(items: data.bangumi),
              const SizedBox(height: 28),
            ],
            if (data.recommendations.isNotEmpty) ...[
              const SectionHeader(title: '热门电影'),
              _MediaRail(items: data.recommendations),
              const SizedBox(height: 28),
            ],
            if (data.trending.isNotEmpty) ...[
              const SectionHeader(title: '近期热门'),
              _MediaRail(items: data.trending),
            ],
          ],
        );
      },
    );
  }
}

class _MediaRail extends StatelessWidget {
  const _MediaRail({required this.items});

  /// 横向列表必须给出确定宽度，否则卡片无法计算尺寸。
  static const double cardWidth = 132;

  final List<MediaItem> items;

  @override
  Widget build(BuildContext context) {
    final hasSubtitle = items.any(
      (item) => item.year.isNotEmpty || item.remarks.isNotEmpty,
    );
    return SizedBox(
      height: PosterCard.estimatedHeight(
        context,
        width: cardWidth,
        hasSubtitle: hasSubtitle,
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final item = items[index];
          return PosterCard(
            item: item,
            width: cardWidth,
            onTap: () => context.push('/detail', extra: [item]),
          );
        },
      ),
    );
  }
}
