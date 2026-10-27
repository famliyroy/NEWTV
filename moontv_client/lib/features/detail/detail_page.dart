import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../domain/models/media_item.dart';
import '../../providers.dart';

class DetailPage extends ConsumerStatefulWidget {
  const DetailPage({required this.initialItem, this.availableSources = const [], super.key});

  final MediaItem initialItem;
  final List<MediaItem> availableSources;

  @override
  ConsumerState<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends ConsumerState<DetailPage> {
  late MediaItem _selectedSource;
  late MediaItem _item;
  var _loading = true;
  String? _error;
  var _selectedEpisode = 0;
  var _favorited = false;
  var _favoriteBusy = false;

  @override
  void initState() {
    super.initState();
    _selectedSource = widget.initialItem;
    _item = widget.initialItem;
    _selectedEpisode = widget.initialItem.lastEpisodeIndex;
    _load();
    _checkFavorite();
  }

  Future<void> _checkFavorite() async {
    final source = _selectedSource;
    try {
      final favorite = await ref
          .read(appDependenciesProvider)
          .mediaRepository
          .isFavorite(source);
      if (mounted && identical(source, _selectedSource)) {
        setState(() => _favorited = favorite);
      }
    } on Object {
      // 收藏状态查询失败不影响主流程。
    }
  }

  Future<void> _toggleFavorite() async {
    if (_favoriteBusy) return;
    setState(() => _favoriteBusy = true);
    final repository = ref.read(appDependenciesProvider).mediaRepository;
    final target = _item;
    try {
      if (_favorited) {
        await repository.deleteFavorite(target);
        if (mounted) setState(() => _favorited = false);
      } else {
        await repository.saveFavorite(target);
        if (mounted) setState(() => _favorited = true);
      }
    } on Object {
      // 网络失败时保持原状态。
    } finally {
      if (mounted) setState(() => _favoriteBusy = false);
    }
  }

  Future<void> _load({bool force = false}) async {
    final source = _selectedSource;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loaded = await ref
          .read(appDependenciesProvider)
          .mediaRepository
          .detail(source, force: force);
      if (!mounted || !identical(source, _selectedSource)) return;
      setState(() {
        _item = loaded;
        _loading = false;
        if (loaded.episodes.isNotEmpty) {
          _selectedEpisode = _selectedEpisode.clamp(0, loaded.episodes.length - 1);
        } else {
          _selectedEpisode = 0;
        }
      });
    } catch (error) {
      if (!mounted || !identical(source, _selectedSource)) return;
      setState(() {
        _loading = false;
        _error = readableError(error);
      });
    }
  }

  void _changeSource(MediaItem source) {
    if (identical(source.source, _selectedSource.source)) return;
    setState(() {
      _selectedSource = source;
      _item = source;
      _selectedEpisode = source.lastEpisodeIndex;
    });
    _load();
    _checkFavorite();
  }

  void _play() {
    final item = _item;
    if (item.episodes.isEmpty) return;
    context.push(
      '/player',
      extra: PlaybackContext(
        item: item,
        episodeIndex: _selectedEpisode.clamp(0, item.episodes.length - 1),
        availableSources: widget.availableSources,
        initialPositionSeconds: _selectedEpisode == item.lastEpisodeIndex
            ? item.playTimeSeconds
            : 0,
      ),
    );
  }

  static String _episodeLabel(MediaItem item, int index) {
    final title = index < item.episodeTitles.length
        ? item.episodeTitles[index].trim()
        : '';
    // 单片（如短剧「全集」）直接用片源返回的标题，不必再叠加集号。
    if (item.episodes.length == 1 && title.isNotEmpty) return title;
    final number = '第 ${index + 1} 集';
    if (title.isEmpty) return number;
    // 纯数字（"01"）或 "第01集" 这类与集号重复的标题只保留集号。
    if (RegExp(r'^\d+(\.\d+)?$').hasMatch(title)) return number;
    final chinese = RegExp(r'^第\s*0*(\d+)\s*集$').firstMatch(title);
    if (chinese != null && int.tryParse(chinese.group(1)!) == index + 1) {
      return number;
    }
    return '$number · $title';
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _Header(
              item: item,
              loading: _loading,
              favorited: _favorited,
              onToggleFavorite: _toggleFavorite,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_error != null) ...[
                    // 详情接口失败时页面仍可用搜索结果播放，这里只做轻提示，
                    // 不展示成严重错误。
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '详情补全失败，当前显示搜索结果：$_error',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          TextButton(
                            onPressed: () => _load(force: true),
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (widget.availableSources.length > 1) ...[
                    Text('播放源', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    _SourceChips(
                      sources: widget.availableSources,
                      selected: _selectedSource,
                      onSelected: _changeSource,
                    ),
                    const SizedBox(height: 20),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '选集',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.sourceName.isEmpty
                              ? '共 ${item.episodes.length} 集'
                              : '${item.sourceName} · 共 ${item.episodes.length} 集',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      if (_loading)
                        const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (item.episodes.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        _loading ? '正在获取选集…' : '该片源没有可用选集，试试切换其他播放源',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var index = 0; index < item.episodes.length; index++)
                          _EpisodeChip(
                            index: index,
                            label: _episodeLabel(item, index),
                            selected: index == _selectedEpisode,
                            onTap: () => setState(() => _selectedEpisode = index),
                          ),
                      ],
                    ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: item.episodes.isEmpty ? null : _play,
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text(
                            item.episodes.isEmpty
                                ? '暂无可播放选集'
                                : '播放 ${_episodeLabel(item, _selectedEpisode.clamp(0, item.episodes.length - 1))}',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton.filledTonal(
                        tooltip: _favorited ? '取消收藏' : '加入收藏',
                        onPressed: _favoriteBusy ? null : _toggleFavorite,
                        icon: Icon(_favorited ? Icons.favorite : Icons.favorite_border),
                      ),
                    ],
                  ),
                  if (item.description.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    Text(
                      '简介',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(item.description, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ],
              ),
            ),
          ],
        ),
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
    final meta = <String>[
      if (item.year.isNotEmpty) item.year,
      if (item.typeName.isNotEmpty) item.typeName,
      if (item.remarks.isNotEmpty) item.remarks,
      if (item.rate.isNotEmpty && item.rate != '0') '评分 ${item.rate}',
    ].join(' · ');

    return SizedBox(
      height: 300,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (item.poster.isNotEmpty)
            CachedNetworkImage(
              imageUrl: item.poster,
              fit: BoxFit.cover,
              fadeInDuration: Duration.zero,
              errorWidget: (context, url, error) => const ColoredBox(color: Colors.black26),
            ),
          // 模糊背景由 RepaintBoundary 包住，避免滚动时反复重绘导致闪烁。
          RepaintBoundary(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: const ColoredBox(color: Color(0xB3000000)),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x66000000), Color(0xCC000000)],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton.filledTonal(
                        onPressed: () => context.pop(),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const Spacer(),
                      if (loading)
                        const Padding(
                          padding: EdgeInsets.only(right: 10),
                          child: SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          ),
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
                        width: 104,
                        child: AspectRatio(
                          aspectRatio: 2 / 3,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: item.poster.isEmpty
                                ? const ColoredBox(color: Colors.white24)
                                : CachedNetworkImage(
                                    imageUrl: item.poster,
                                    fit: BoxFit.cover,
                                    fadeInDuration: Duration.zero,
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              item.title.isEmpty ? '未知作品' : item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            if (meta.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                meta,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 12),
                              ),
                            ],
                          ],
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

class _SourceChips extends StatelessWidget {
  const _SourceChips({
    required this.sources,
    required this.selected,
    required this.onSelected,
  });

  final List<MediaItem> sources;
  final MediaItem selected;
  final ValueChanged<MediaItem> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: sources.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final source = sources[index];
          final isSelected = source.source == selected.source;
          return ChoiceChip(
            selected: isSelected,
            label: Text(
              source.episodes.isEmpty
                  ? source.sourceName
                  : '${source.sourceName} · ${source.episodes.length} 集',
            ),
            labelStyle: TextStyle(
              fontSize: 12,
              color: isSelected ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
            selectedColor: scheme.primary,
            onSelected: (_) => onSelected(source),
          );
        },
      ),
    );
  }
}

class _EpisodeChip extends StatelessWidget {
  const _EpisodeChip({
    required this.index,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primary : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? scheme.onPrimary : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
