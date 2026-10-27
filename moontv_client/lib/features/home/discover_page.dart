import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/media_item.dart';
import '../../providers.dart';
import '../../shared/widgets/error_view.dart';
import '../../shared/widgets/skeleton_box.dart';

/// 发现页数据：按分类从服务端取推荐，`trending` 为混合热门榜。
final discoverFeedProvider =
    FutureProvider.autoDispose.family<List<MediaItem>, String>((ref, kind) {
  final repository = ref.watch(appDependenciesProvider).mediaRepository;
  if (kind == 'trending') return repository.trending();
  return repository.discoverFeed(kind);
});

class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage>
    with SingleTickerProviderStateMixin {
  static const _tabs = <({String key, String label, String subtitle})>[
    (key: 'movie', label: '电影', subtitle: '豆瓣热门电影'),
    (key: 'tv', label: '剧集', subtitle: '豆瓣热门剧集'),
    (key: 'trending', label: '热门', subtitle: '近期热门榜单'),
  ];

  late final TabController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(
            children: [
              Expanded(
                child: Text('发现', style: Theme.of(context).textTheme.headlineSmall),
              ),
              IconButton.filledTonal(
                tooltip: '刷新',
                onPressed: () {
                  for (final tab in _tabs) {
                    ref.invalidate(discoverFeedProvider(tab.key));
                  }
                },
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        TabBar(
          controller: _controller,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final tab in _tabs) Tab(text: tab.label)],
        ),
        Expanded(
          child: TabBarView(
            controller: _controller,
            children: [
              for (final tab in _tabs)
                _FeedView(kind: tab.key, title: tab.subtitle),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeedView extends ConsumerWidget {
  const _FeedView({required this.kind, required this.title});

  final String kind;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(discoverFeedProvider(kind));
    return feed.when(
      loading: () => const _FeedSkeleton(),
      error: (error, stackTrace) => ErrorView(
        message: '加载失败：$error',
        onRetry: () => ref.invalidate(discoverFeedProvider(kind)),
      ),
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('该分类暂时没有数据'),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => ref.invalidate(discoverFeedProvider(kind)),
                  child: const Text('重新加载'),
                ),
              ],
            ),
          );
        }
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${items.length} 部',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 150,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.56,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = items[index];
                    return _DiscoverCard(
                      item: item,
                      // 豆瓣条目本身没有播放源，点击后按标题去各源搜索。
                      onTap: () => context.push('/search', extra: item.title),
                    );
                  },
                  childCount: items.length,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DiscoverCard extends StatelessWidget {
  const _DiscoverCard({required this.item, required this.onTap});

  final MediaItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rating = item.rate.trim();
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (item.poster.isEmpty)
                    ColoredBox(color: scheme.surfaceContainerHighest)
                  else
                    CachedNetworkImage(
                      imageUrl: item.poster,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 120),
                      placeholder: (context, url) => const SkeletonBox(height: 180),
                      errorWidget: (context, url, error) => ColoredBox(
                        color: scheme.surfaceContainerHighest,
                        child: const Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  if (rating.isNotEmpty && rating != '0')
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.66),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          rating,
                          style: const TextStyle(
                            color: Color(0xFFFFB74D),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (item.year.isNotEmpty)
            Text(item.year, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _FeedSkeleton extends StatelessWidget {
  const _FeedSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 110),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.56,
      ),
      itemCount: 9,
      itemBuilder: (context, index) => const SkeletonBox(height: 240),
    );
  }
}
