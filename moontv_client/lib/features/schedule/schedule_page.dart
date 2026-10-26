import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/media_item.dart';
import '../../providers.dart';
import '../../shared/widgets/empty_view.dart';
import '../../shared/widgets/error_view.dart';
import '../../shared/widgets/poster_card.dart';

class SchedulePage extends ConsumerWidget {
  const SchedulePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<MediaItem>>(
      future: ref.read(appDependenciesProvider).mediaRepository.bangumi(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return ErrorView(message: snapshot.error.toString());
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final items = snapshot.data!;
        if (items.isEmpty) return const EmptyView(title: '本周暂无数据', message: '新番表由服务端数据源提供');
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
