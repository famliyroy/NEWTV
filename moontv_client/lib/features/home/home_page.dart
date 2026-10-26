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
});

final homeDataProvider = FutureProvider.autoDispose<HomeData>((ref) async {
  final repository = ref.read(appDependenciesProvider).mediaRepository;
  Future<List<MediaItem>> safe(Future<List<MediaItem>> future) =>
      future.catchError((_) => <MediaItem>[]);
  final results = await Future.wait([
    safe(repository.history()),
    safe(repository.recommendations()),
    safe(repository.bangumi()),
  ]);
  return (
    history: results[0],
    recommendations: results[1],
    bangumi: results[2],
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
        if (data.history.isEmpty && data.recommendations.isEmpty && data.bangumi.isEmpty) {
          return EmptyView(
            title: '开始你的第一部作品',
            message: '从搜索页查找电影、剧集或番剧',
            actionLabel: '去搜索',
            onAction: () => context.push('/search'),
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
              const SectionHeader(title: '热门推荐'),
              _MediaRail(items: data.recommendations),
            ],
          ],
        );
      },
    );
  }
}

class _MediaRail extends StatelessWidget {
  const _MediaRail({required this.items});

  final List<MediaItem> items;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 238,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final item = items[index];
          return PosterCard(
            item: item,
            onTap: () => context.push('/detail', extra: [item]),
          );
        },
      ),
    );
  }
}
