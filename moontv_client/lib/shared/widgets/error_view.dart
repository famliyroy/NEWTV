import 'package:flutter/material.dart';

import 'empty_view.dart';

class ErrorView extends StatelessWidget {
  const ErrorView({required this.message, this.onRetry, super.key});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyView(
      icon: Icons.cloud_off_outlined,
      title: '加载失败',
      message: message,
      actionLabel: onRetry == null ? null : '重试',
      onAction: onRetry,
    );
  }
}
