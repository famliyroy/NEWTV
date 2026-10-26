import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moontv_client/shared/widgets/empty_view.dart';

void main() {
  testWidgets('empty view renders title, message and action', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: EmptyView(
            title: '暂无内容',
            message: '去搜索',
            actionLabel: '开始',
            onAction: () => tapped = true,
          ),
        ),
      ),
    );
    expect(find.text('暂无内容'), findsOneWidget);
    expect(find.text('去搜索'), findsOneWidget);
    await tester.tap(find.text('开始'));
    expect(tapped, isTrue);
  });
}
