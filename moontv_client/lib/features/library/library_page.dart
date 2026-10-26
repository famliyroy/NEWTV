import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/media_item.dart';
import '../../providers.dart';
import '../../shared/widgets/empty_view.dart';
import '../../shared/widgets/error_view.dart';
import '../../shared/widgets/poster_card.dart';

class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(appDependenciesProvider).mediaRepository;
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(tabs: [Tab(text: '收藏'), Tab(text: '历史')]),
          Expanded(
            child: TabBarView(
              children: [
                _MediaList(
                  loader: repo.favorites,
                  onDelete: repo.deleteFavorite,
                  emptyTitle: '暂无收藏作品',
                ),
                _MediaList(
                  loader: repo.history,
                  onDelete: repo.deletePlayRecord,
                  emptyTitle: '暂无观看历史',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaList extends StatefulWidget {
  const _MediaList({
    required this.loader,
    required this.onDelete,
    required this.emptyTitle,
  });

  final Future<List<MediaItem>> Function() loader;
  final Future<void> Function(MediaItem item) onDelete;
  final String emptyTitle;

  @override
  State<_MediaList> createState() => _MediaListState();
}

class _MediaListState extends State<_MediaList> {
  late Future<List<MediaItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loader();
  }

  void _reload() {
    setState(() => _future = widget.loader());
  }

  Future<void> _remove(MediaItem item) async {
    await widget.onDelete(item);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MediaItem>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorView(message: snapshot.error.toString(), onRetry: _reload);
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final items = snapshot.data!;
        if (items.isEmpty) return EmptyView(title: widget.emptyTitle);
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.52,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Stack(
                children: [
                  PosterCard(item: item, onTap: () => context.push('/detail', extra: [item])),
                  if (item.source.isNotEmpty && item.id.isNotEmpty)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: IconButton.filledTonal(
                        visualDensity: VisualDensity.compact,
                        tooltip: '移除',
                        onPressed: () => _remove(item),
                        icon: const Icon(Icons.close, size: 16),
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
