import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/utils/media_grouping.dart';
import '../../core/utils/playback_resume.dart';
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

  /// 用户是否手动点过选集：点过就不再用播放记录覆盖选集位置。
  var _episodePickedByUser = false;

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
        // 详情拿到集数后补全「上次看到哪一集、哪一秒」。
        await _applyPlayRecord();
      }
    } catch (error) {
      if (!mounted || !identical(source, _selectedSource)) return;
      setState(() {
        _loading = false;
        _error = readableError(error);
      });
    }
  }

  /// 用播放记录补全续播点。
  ///
  /// 之前只有从首页「继续观看」进的条目才带 lastEpisodeIndex/playTimeSeconds，
  /// 从搜索/发现/推荐进来的恒为 0，所以永远从头播。
  Future<void> _applyPlayRecord() async {
    final item = _item;
    if (item.episodes.isEmpty) return;
    final key = _selectedSource.storageKey;
    try {
      final record = await ref
          .read(appDependenciesProvider)
          .mediaRepository
          .playRecordFor(item);
      if (!mounted || record == null) return;
      // 期间可能切了片源/换了集，迟到的结果直接丢弃。
      if (_selectedSource.storageKey != key || _item.episodes.isEmpty) return;
      final point = resolveResumePoint(item: _item, record: record);
      if (point == null) return;
      setState(() {
        _item = _item.copyWith(
          lastEpisodeIndex: point.episodeIndex,
          // 片尾记录不再续播末段，只定位集数。
          playTimeSeconds: point.startSeconds,
          totalTimeSeconds: point.totalSeconds,
        );
        // 用户手动选过集就不许被迟到的异步查询改回去。
        if (!_episodePickedByUser) _selectedEpisode = point.episodeIndex;
      });
    } on Object {
      // 记录拉取失败不影响详情展示。
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
      _episodePickedByUser = false;
    });
    _load(autoFallback: false);
    _checkFavorite();
  }

  /// 手动搜索更多片源：命中组会追加进 `_sources` 并直接切换过去。
  Future<void> _openSourceSearch() async {
    final group = await showModalBottomSheet<List<MediaItem>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => _SourceSearchSheet(initialQuery: _item.title),
    );
    if (group == null || group.isEmpty || !mounted) return;
    final primary = _mergeMetadata(group.first, _item);
    final merged = <MediaItem>[];
    final seen = <String>{};
    for (final item in [..._sources, ...group]) {
      if (!seen.add(item.storageKey)) continue;
      merged.add(
        item.storageKey == primary.storageKey ? primary : _mergeMetadata(item, _item),
      );
    }
    setState(() {
      _sources = merged;
      _selectedSource = primary;
      _item = primary;
      _selectedEpisode = primary.lastEpisodeIndex;
      _emptySources.remove(primary.storageKey);
    });
    await _load(autoFallback: false);
    await _checkFavorite();
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
        // 只有选中集等于记录集数才续播，其它集一律从头。
        initialPositionSeconds: resumeStartSeconds(
          item: item,
          selectedEpisode: _selectedEpisode,
        ),
      ),
    );
  }

  static String _formatSeconds(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final rest = seconds % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = rest.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
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
                  // 播放源常驻展示：即使只命中 1 个源，也要让用户看到当前源与集数，
                  // 并提供「搜索更多源」入口，否则单源时完全没有换源途径。
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('播放源', style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _resolvingSources ? null : _openSourceSearch,
                        icon: const Icon(Icons.travel_explore, size: 18),
                        label: const Text('搜索更多源'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (_sources.isEmpty)
                    Text(
                      _resolvingSources ? '正在匹配片源…' : '尚未匹配到片源，可手动搜索',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  else
                    _SourceChips(
                      sources: _sources,
                      selected: _selectedSource,
                      emptyKeys: _emptySources,
                      onSelected: _changeSource,
                    ),
                  const SizedBox(height: 20),
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
                            resume: index == item.lastEpisodeIndex &&
                                item.playTimeSeconds > 0,
                            onTap: () => setState(() {
                              _selectedEpisode = index;
                              _episodePickedByUser = true;
                            }),
                          ),
                      ],
                    ),
                  if (item.playTimeSeconds > 0 && item.episodes.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          Icons.history,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '上次看到 ${_episodeLabel(item, item.lastEpisodeIndex.clamp(0, item.episodes.length - 1))} ${_formatSeconds(item.playTimeSeconds)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        if (_selectedEpisode != item.lastEpisodeIndex)
                          TextButton(
                            onPressed: () => setState(() {
                              _selectedEpisode = item.lastEpisodeIndex
                                  .clamp(0, item.episodes.length - 1);
                              _episodePickedByUser = true;
                            }),
                            child: const Text('回到上次'),
                          ),
                      ],
                    ),
                  ],
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
    required this.emptyKeys,
    required this.onSelected,
  });

  final List<MediaItem> sources;
  final MediaItem selected;

  /// 详情接口返回 0 集的源（多为源站已失效），在 chip 上标注出来。
  final Set<String> emptyKeys;
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
          final isSelected = source.storageKey == selected.storageKey;
          final name = source.sourceName.isEmpty ? source.source : source.sourceName;
          final empty = emptyKeys.contains(source.storageKey);
          return ChoiceChip(
            selected: isSelected,
            label: Text(
              empty
                  ? '$name · 无选集'
                  : '$name · ${source.episodes.length} 集',
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

/// 手动搜索更多片源：把候选组按标题聚合展示，选中即把整组追加进详情页的源列表。
class _SourceSearchSheet extends ConsumerStatefulWidget {
  const _SourceSearchSheet({required this.initialQuery});

  final String initialQuery;

  @override
  ConsumerState<_SourceSearchSheet> createState() => _SourceSearchSheetState();
}

class _SourceSearchSheetState extends ConsumerState<_SourceSearchSheet> {
  late final TextEditingController _controller;
  var _loading = false;
  String? _error;
  List<List<MediaItem>> _groups = const [];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    unawaited(_search());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await ref
          .read(appDependenciesProvider)
          .mediaRepository
          .search(keyword);
      if (!mounted) return;
      final groups = groupByTitle(
        results.where((item) => item.source.isNotEmpty),
      )..sort((a, b) => b.length.compareTo(a.length));
      setState(() {
        _loading = false;
        _groups = groups;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = readableError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    // 键盘弹起后剩余高度再取 72%，避免「固定高度 + 底部 inset」把内容挤出屏幕。
    final available = MediaQuery.sizeOf(context).height - insets;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: SizedBox(
        height: available * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text('搜索更多片源', style: theme.textTheme.titleMedium),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => unawaited(_search()),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '输入片名后搜索',
                        prefixIcon: Icon(Icons.search, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _loading ? null : () => unawaited(_search()),
                    child: const Text('搜索'),
                  ),
                ],
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Text(_error!, style: theme.textTheme.bodySmall),
              )
            else if (_groups.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Text('没有搜到其他片源，换个关键词试试', style: theme.textTheme.bodySmall),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                  itemCount: _groups.length,
                  itemBuilder: (context, index) {
                    final group = _groups[index];
                    final first = group.first;
                    final names = group
                        .map((item) => item.sourceName.isEmpty ? item.source : item.sourceName)
                        .toSet()
                        .take(4)
                        .join('、');
                    return ListTile(
                      leading: const Icon(Icons.movie_outlined),
                      title: Text(first.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        [
                          if (first.year.isNotEmpty) first.year,
                          '${group.length} 个源',
                          names,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).pop(group),
                    );
                  },
                ),
              ),
          ],
        ),
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
    this.resume = false,
  });

  final int index;
  final String label;
  final bool selected;

  /// 该集是上次观看的位置，加「上次」角标。
  final bool resume;
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (resume) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: (selected ? scheme.onPrimary : scheme.primary)
                        .withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '上次',
                    style: TextStyle(
                      fontSize: 9,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      color: selected ? scheme.onPrimary : scheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? scheme.onPrimary : scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
