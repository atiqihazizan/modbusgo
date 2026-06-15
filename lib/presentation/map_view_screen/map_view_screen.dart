import 'package:flutter/material.dart';

import '../../core/app_export.dart';
import '../../core/services/local_storage_service.dart';
import '../home_screen/widgets/lora_webview_widget.dart';

class MapViewScreen extends StatelessWidget {
  const MapViewScreen({super.key});

  Future<String> _buildUrl() async {
    final info = await LocalStorageService().getDeviceInfo();
    final deviceId = info?['device_id'];
    if (deviceId == null || deviceId.isEmpty) {
      return LoraWebViewWidget.defaultUrl;
    }
    return '${LoraWebViewWidget.defaultUrl}?device=$deviceId';
  }

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
      body: FutureBuilder<String>(
        future: _buildUrl(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: theme.colorScheme.primary,
              ),
            );
          }
          return SafeArea(
            top: false,
            child: LoraWebViewWidget(url: snapshot.data!, fullScreen: true),
          );
        },
      ),
    );
  }
}
