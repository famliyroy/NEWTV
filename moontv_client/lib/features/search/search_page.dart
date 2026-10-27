import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/debouncer.dart';
import '../../core/utils/media_grouping.dart';
import '../../data/repositories/search_history_store.dart';
import '../../domain/models/media_item.dart';
import '../../providers.dart';
import '../../shared/widgets/empty_view.dart';
import '../../shared/widgets/error_view.dart';
import '../../shared/widgets/poster_card.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({this.initialQuery, super.key});

  /// 从发现页 / 新番表点进来时携带的关键词，进入即自动搜索。
  final String? initialQuery;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  final _debouncer = Debouncer(const Duration(milliseconds: 300));
  late final SearchHistoryStore _history;
  var _loading = false;
  var _searched = false;
  String? _error;
  List<MediaItem> _results = const [];
  List<String> _historyItems = const [];

  @override
  void initState() {
    super.initState();
    _history = SearchHistoryStore(ref.read(appDependenciesProvider).preferences);
    _historyItems = _history.load();
    _controller.addListener(() {
      final value = _controller.text;
      _debouncer(() {
        if (value.trim().isNotEmpty) _search(value);
      });
    });
    final initial = widget.initialQuery?.trim() ?? '';
    if (initial.isNotEmpty) {
      _controller.text = initial;
      WidgetsBinding.instance.addPostFrameCallback((_) => _search(initial));
    }
  }

  @override
  void dispose() {
    _debouncer.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    setState(() {
      _loading = true;
      _searched = true;
      _error = null;
    });
    try {
      final result = await ref.read(appDependenciesProvider).mediaRepository.search(query.trim());
      await _history.add(query);
      if (!mounted) return;
      setState(() {
        _results = result;
        _historyItems = _history.load();
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<List<MediaItem>> _grouped() => groupByTitle(_results);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '搜索电影、剧集、番剧…',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() {
                      _controller.clear();
                      _results = const [];
                      _searched = false;
                      _error = null;
                    }),
                  ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(999)),
            filled: true,
          ),
          onSubmitted: _search,
        ),
        bottom: _loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return ErrorView(message: _error!, onRetry: () => _search(_controller.text));
    }
    if (!_searched) {
      if (_historyItems.isEmpty) {
        return const EmptyView(title: '搜索你的片库', message: '输入作品名称即可开始');
      }
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(child: Text('最近搜索', style: Theme.of(context).textTheme.titleMedium)),
              TextButton(
                onPressed: () async {
                  await _history.clear();
                  setState(() => _historyItems = const []);
                },
                child: const Text('清空'),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in _historyItems)
                InputChip(
                  label: Text(item),
                  onPressed: () {
                    _controller.text = item;
                    _search(item);
                  },
                  onDeleted: () async {
                    await _history.remove(item);
                    setState(() => _historyItems = _history.load());
                  },
                ),
            ],
          ),
        ],
      );
    }
    if (!_loading && _results.isEmpty) {
      return EmptyView(title: '没找到「${_controller.text}」', message: '试试别名、原名或更短的关键词');
    }
    final groups = _grouped();
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.52,
      ),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        final item = group.first;
        return Stack(
          children: [
            PosterCard(
              item: item,
              onTap: () => context.push('/detail', extra: group),
            ),
            if (group.length > 1)
              Positioned(
                top: 8,
                right: 8,
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('${group.length} 源'),
                ),
              ),
          ],
        );
      },
    );
  }
}
