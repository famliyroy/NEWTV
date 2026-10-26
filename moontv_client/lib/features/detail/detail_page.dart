import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../domain/models/media_item.dart';
import '../../providers.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/skeleton_box.dart';

class DetailPage extends ConsumerStatefulWidget {
  const DetailPage({required this.initialItem, this.availableSources = const [], super.key});

  final MediaItem initialItem;
  final List<MediaItem> availableSources;

  @override
  ConsumerState<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends ConsumerState<DetailPage> {
  late MediaItem _selectedSource;
  late Future<MediaItem> _future;
  var _selectedEpisode = 0;
  var _favorited = false;
  var _favoriteBusy = false;

  @override
  void initState() {
    super.initState();
    _selectedSource = widget.initialItem;
    _selectedEpisode = widget.initialItem.lastEpisodeIndex;
    _future = _load();
    _checkFavorite();
  }

  Future<void> _checkFavorite() async {
    try {
      final fav = await ref.read(appDependenciesProvider).mediaRepository.isFavorite(_selectedSource);
      if (mounted) setState(() => _favorited = fav);
    } on Object {
      // Ignore favorite check failures.
    }
  }

  Future<void> _toggleFavorite(MediaItem item) async {
    if (_favoriteBusy) return;
    setState(() => _favoriteBusy = true);
    final repo = ref.read(appDependenciesProvider).mediaRepository;
    try {
      if (_favorited) {
        await repo.deleteFavorite(item);
        if (mounted) setState(() => _favorited = false);
      } else {
        await repo.saveFavorite(item);
        if (mounted) setState(() => _favorited = true);
      }
    } on Object {
      // Keep previous state on network error.
    } finally {
      if (mounted) setState(() => _favoriteBusy = false);
    }
  }

  Future<MediaItem> _load({bool force = false}) async {
    final loaded = await ref.read(appDependenciesProvider).mediaRepository.detail(
          _selectedSource,
          force: force,
        );
    if (mounted && loaded.episodes.isNotEmpty) {
      final clamped = _selectedEpisode.clamp(0, loaded.episodes.length - 1);
      if (clamped != _selectedEpisode) {
        setState(() => _selectedEpisode = clamped);
      }
    }
    return loaded;
  }

  void _changeSource(MediaItem source) {
    setState(() {
      _selectedSource = source;
      _future = _load();
    });
    _checkFavorite();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<MediaItem>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(readableError(snapshot.error!)),
                  TextButton(onPressed: () => setState(() => _future = _load(force: true)), child: const Text('重试')),
                ],
              ),
            );
          }
          final item = snapshot.data ?? _selectedSource;
          final safeEpisode = item.episodes.isEmpty
              ? 0
              : _selectedEpisode.clamp(0, item.episodes.length - 1);
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _Header(
                  item: item,
                  loading: snapshot.connectionState == ConnectionState.waiting,
                  favorited: _favorited,
                  onToggleFavorite: () => _toggleFavorite(item),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.availableSources.length > 1) ...[
                        Row(
                          children: [
                            Text('选源', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _selectedSource.source,
                                decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                                items: [
                                  for (final source in widget.availableSources)
                                    DropdownMenuItem(value: source.source, child: Text(source.sourceName)),
                                ],
                                onChanged: (value) {
                                  final selected = widget.availableSources.firstWhere((item) => item.source == value);
                                  _changeSource(selected);
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                      ],
                      Text('选集（共 ${item.episodes.length} 集）', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 52,
                        child: item.episodes.isEmpty
                            ? const SkeletonBox(height: 44)
                            : ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: item.episodes.length,
                                separatorBuilder: (context, index) => const SizedBox(width: 8),
                                itemBuilder: (context, index) {
                                  final selected = index == safeEpisode;
                                  return FilledButton.tonal(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: selected ? Theme.of(context).colorScheme.primary : null,
                                      foregroundColor: selected ? Theme.of(context).colorScheme.onPrimary : null,
                                    ),
                                    onPressed: () => setState(() => _selectedEpisode = index),
                                    child: Text(item.episodeLabel(index)),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton.icon(
                            onPressed: item.episodes.isEmpty
                                ? null
                                : () => context.push(
                                      '/player',
                                      extra: PlaybackContext(
                                        item: item,
                                        episodeIndex: safeEpisode,
                                        availableSources: widget.availableSources,
                                        initialPositionSeconds:
                                            safeEpisode == item.lastEpisodeIndex
                                                ? item.playTimeSeconds
                                                : 0,
                                      ),
                                    ),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: Text('播放 ${item.episodeLabel(safeEpisode)}'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _favoriteBusy ? null : () => _toggleFavorite(item),
                            icon: Icon(_favorited ? Icons.favorite : Icons.favorite_border),
                            label: Text(_favorited ? '已收藏' : '加入收藏'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.item,
    required this.loading,
    required this.favorited,
    required this.onToggleFavorite,
  });

  final MediaItem item;
  final bool loading;
  final bool favorited;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 360,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (item.poster.isNotEmpty)
            CachedNetworkImage(imageUrl: item.poster, fit: BoxFit.cover),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
            child: Container(color: Colors.black.withValues(alpha: 0.48)),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton.filledTonal(onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back)),
                      const Spacer(),
                      if (loading)
                        const Padding(
                          padding: EdgeInsets.only(right: 12),
                          child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                      IconButton.filledTonal(
                        tooltip: favorited ? '取消收藏' : '收藏',
                        onPressed: onToggleFavorite,
                        icon: Icon(favorited ? Icons.favorite : Icons.favorite_border),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      SizedBox(
                        width: 116,
                        child: AspectRatio(
                          aspectRatio: 2 / 3,
                          child: Hero(
                            tag: 'poster-${item.storageKey}-${item.title}',
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: item.poster.isEmpty
                                  ? Container(color: Colors.white24)
                                  : CachedNetworkImage(imageUrl: item.poster, fit: BoxFit.cover),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: GlassCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(item.title, style: Theme.of(context).textTheme.displaySmall?.copyWith(color: Colors.white)),
                              const SizedBox(height: 8),
                              Text(
                                [item.year, item.typeName, item.remarks].where((e) => e.isNotEmpty).join(' · '),
                                style: const TextStyle(color: Colors.white70),
                              ),
                              if (item.description.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Text(item.description, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70)),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
