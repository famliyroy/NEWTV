import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/empty_view.dart';

class DiscoverPage extends StatelessWidget {
  const DiscoverPage({super.key});

  @override
  Widget build(BuildContext context) {
    return EmptyView(
      icon: Icons.explore_outlined,
      title: '发现更多内容',
      message: '推荐与榜单数据来自你的 MoonTVPlus 服务器。也可以直接搜索。',
      actionLabel: '打开搜索',
      onAction: () => context.push('/search'),
    );
  }
}
