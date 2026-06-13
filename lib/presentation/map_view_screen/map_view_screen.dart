import 'package:flutter/material.dart';

import '../../core/app_export.dart';
import '../home_screen/widgets/lora_webview_widget.dart';

class MapViewScreen extends StatelessWidget {
  const MapViewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 2,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: CustomIconWidget(
            iconName: 'arrow_back',
            color: theme.colorScheme.onSurface,
            size: 22,
          ),
          tooltip: 'Back',
        ),
        title: Text(
          'Map View',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
      body: const SafeArea(
        top: false,
        child: LoraWebViewWidget(fullScreen: true),
      ),
    );
  }
}
