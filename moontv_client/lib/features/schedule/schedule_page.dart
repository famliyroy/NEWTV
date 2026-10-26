import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/media_item.dart';
import '../../providers.dart';
import '../../shared/widgets/empty_view.dart';
import '../../shared/widgets/error_view.dart';
import '../../shared/widgets/poster_card.dart';

class SchedulePage extends ConsumerStatefulWidget {
  const SchedulePage({super.key});

  @override
  ConsumerState<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends ConsumerState<SchedulePage> {
  static const _weekdays = [
    (label: '全部', keys: <String>[]),
    (label: '周一', keys: ['1', 'mon', 'monday', '周一', '星期一']),
    (label: '周二', keys: ['2', 'tue', 'tuesday', '周二', '星期二']),
    (label: '周三', keys: ['3', 'wed', 'wednesday', '周三', '星期三']),
    (label: '周四', keys: ['4', 'thu', 'thursday', '周四', '星期四']),
    (label: '周五', keys: ['5', 'fri', 'friday', '周五', '星期五']),
    (label: '周六', keys: ['6', 'sat', 'saturday', '周六', '星期六']),
    (label: '周日', keys: ['7', '0', 'sun', 'sunday', '周日', '星期日', '星期天']),
  ];

  int _selectedDay = 0;

  List<MediaItem> _filterByDay(List<MediaItem> items) {
    if (_selectedDay == 0) return items;
    final keys = _weekdays[_selectedDay].keys;
    final matched = items.where((item) {
      final tag = '${item.typeName} ${item.remarks}'.toLowerCase();
      return keys.any(tag.contains);
    }).toList();
    return matched;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MediaItem>>(
      future: ref.read(appDependenciesProvider).mediaRepository.bangumi(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return ErrorView(message: snapshot.error.toString());
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final allItems = snapshot.data!;
        if (allItems.isEmpty) {
          return const EmptyView(title: '本周暂无数据', message: '新番表由服务端数据源提供');
        }
        final items = _filterByDay(allItems);
        return Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                children: [
                  for (var i = 0; i < _weekdays.length; i++) ...[
                    ChoiceChip(
                      label: Text(_weekdays[i].label),
                      selected: _selectedDay == i,
                      onSelected: (_) => setState(() => _selectedDay = i),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? const EmptyView(title: '当日暂无排期', message: '可切换其他日期查看')
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
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
                    ),
            ),
          ],
        );
      },
    );
  }
}
