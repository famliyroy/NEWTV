import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/utils/media_grouping.dart';
import '../../domain/models/media_item.dart';
import '../../providers.dart';
import '../../shared/widgets/smart_image.dart';

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
  late List<MediaItem> _sources;
  var _loading = true;
  String? _error;
  var _selectedEpisode = 0;
  var _favorited = false;
  var _favoriteBusy = false;
  var _resolvingSources = false;

  @override
  void initState() {
    super.initState();
    _selectedSource = widget.initialItem;
    _item = widget.initialItem;
    _sources = List<MediaItem>.of(widget.availableSources);
    if (_sources.isEmpty && widget.initialItem.source.isNotEmpty) {
      _sources = [widget.initialItem];
    }
    _selectedEpisode = widget.initialItem.lastEpisodeIndex;
    if (_sources.isEmpty) {
      // 豆瓣 / TMDB / 番剧表条目没有片源代码，先按标题聚合搜索接源。
      _resolveSources();
    } else {
      _load();
      _checkFavorite();
    }
  }

  /// 用标题调 `/api/search`，把豆瓣/TMDB 条目换成真实片源组。
  Future<void> _resolveSources() async {
    if (_resolvingSources) return;
    _resolvingSources = true;
    setState(() {
      _loading = true;
      _error = null;
    });
    final target = widget.initialItem;
    try {
      final results = await ref
          .read(appDependenciesProvider)
          .mediaRepository
          .search(target.title);
      if (!mounted) return;
      final group = pickBestGroup(target, results);
      if (group == null || group.isEmpty) {
        setState(() {
          _loading = false;
          _error = '未在任何片源找到该片，可换个关键词手动搜索';
        });
        return;
      }
      // 用豆瓣/TMDB 的元数据补齐片源条目缺失的海报、简介、年份与评分。
      final primary = _mergeMetadata(group.first, target);
      if (!mounted) return;
      setState(() {
        _sources = [primary, ...group.skip(1)];
        _selectedSource = primary;
        _item = primary;
        _selectedEpisode = primary.lastEpisodeIndex;
      });
      await _load();
      await _checkFavorite();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = readableError(error);
      });
    } finally {
      _resolvingSources = false;
    }
  }

  static MediaItem _mergeMetadata(MediaItem source, MediaItem meta) {
    return source.copyWith(
      title: source.title.trim().isEmpty ? meta.title : source.title,
      poster: source.poster.trim().isEmpty ? meta.poster : source.poster,
      description:
          source.description.trim().isEmpty ? meta.description : source.description,
      year: source.year.trim().isEmpty ? meta.year : source.year,
      rate: source.rate.trim().isEmpty ? meta.rate : source.rate,
      doubanId: source.doubanId.isEmpty ? meta.doubanId : source.doubanId,
    );
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

  /// 详情接口返回 0 集的源（部分源站已失效），自动切到同组下一个源。
  final _emptySources = <String>{};

  Future<void> _load({bool force = false, bool autoFallback = true}) async {
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
      if (loaded.episodes.isEmpty) {
        _emptySources.add(source.storageKey);
        if (autoFallback) {
          final alternative = _nextUsableSource();
          if (alternative != null) {
            setState(() {
              _selectedSource = alternative;
              _item = alternative;
              _selectedEpisode = alternative.lastEpisodeIndex;
            });
            return await _load(force: force, autoFallback: true);
          }
        }
      } else {
        _emptySources.remove(source.storageKey);
      }
    } catch (error) {
      if (!mounted || !identical(source, _selectedSource)) return;
      setState(() {
        _loading = false;
        _error = readableError(error);
      });
    }
  }

  /// 找一个还没试过、且已知有集数的源。
  MediaItem? _nextUsableSource() {
    for (final candidate in _sources) {
      if (_emptySources.contains(candidate.storageKey)) continue;
      if (candidate.storageKey == _selectedSource.storageKey) continue;
      return candidate;
    }
    return null;
  }

  void _changeSource(MediaItem source) {
    if (source.source == _selectedSource.source && source.id == _selectedSource.id) {
      return;
    }
    setState(() {
      _selectedSource = source;
      _item = source;
      _selectedEpisode = source.lastEpisodeIndex;
    });
    _load(autoFallback: false);
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
        availableSources: _sources,
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
                              _sources.isEmpty
                                  ? _error!
                                  : '详情补全失败，当前显示搜索结果：$_error',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          TextButton(
                            onPressed: _sources.isEmpty
                                ? _resolveSources
                                : () => _load(force: true),
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_sources.length > 1) ...[
                    Text('播放源', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    _SourceChips(
                      sources: _sources,
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
                        _loading
                            ? '正在获取选集…'
                            : _sources.isEmpty
                                ? '未找到可用片源，可返回搜索该片'
                                : '该片源没有可用选集，试试切换其他播放源',
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
            SmartImage(
              url: item.poster,
              errorBuilder: (context) => const ColoredBox(color: Colors.black26),
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
                                : SmartImage(
                                    url: item.poster,
                                    errorBuilder: (context) =>
                                        const ColoredBox(color: Colors.white24),
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
