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
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(tabs: [Tab(text: '收藏'), Tab(text: '历史')]),
          Expanded(
            child: TabBarView(
              children: [
                _MediaList(loader: () => ref.read(appDependenciesProvider).mediaRepository.favorites()),
                _MediaList(loader: () => ref.read(appDependenciesProvider).mediaRepository.history()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaList extends StatelessWidget {
  const _MediaList({required this.loader});

  final Future<List<MediaItem>> Function() loader;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MediaItem>>(
      future: loader(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return ErrorView(message: snapshot.error.toString());
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final items = snapshot.data!;
        if (items.isEmpty) return const EmptyView(title: '暂无记录');
        return GridView.builder(
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
            return PosterCard(item: item, onTap: () => context.push('/detail', extra: [item]));
          },
        );
      },
    );
  }
}
