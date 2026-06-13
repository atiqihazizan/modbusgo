import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class LoraWebViewWidget extends StatefulWidget {
  static const String defaultUrl = 'https://lora2u.com/v2/';

  /// `true` = isi ruang parent (skrin penuh); `false` = tinggi tetap skrin.
  const LoraWebViewWidget({
    super.key,
    this.url = defaultUrl,
    this.fullScreen = false,
  });

  final String url;
  final bool fullScreen;

  static const String _mobileViewportScript = '''
(function() {
  var meta = document.querySelector('meta[name="viewport"]');
  if (!meta) {
    meta = document.createElement('meta');
    meta.setAttribute('name', 'viewport');
    document.head.appendChild(meta);
  }
  meta.setAttribute(
    'content',
    'width=device-width, initial-scale=1.0, maximum-scale=5.0, viewport-fit=cover'
  );
  document.documentElement.style.width = '100%';
  document.documentElement.style.overflowX = 'hidden';
  document.body.style.width = '100%';
  document.body.style.margin = '0';
  document.body.style.overflowX = 'hidden';
})();
''';

  @override
  State<LoraWebViewWidget> createState() => _LoraWebViewWidgetState();
}

class _LoraWebViewWidgetState extends State<LoraWebViewWidget> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF5F5F5))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() => _isLoading = true);
          },
          onPageFinished: (_) => _onPageFinished(),
          onWebResourceError: (_) {
            if (!mounted) return;
            setState(() => _isLoading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _onPageFinished() async {
    await _controller.runJavaScript(LoraWebViewWidget._mobileViewportScript);
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.sizeOf(context);

    final webView = Stack(
      fit: StackFit.expand,
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading)
          ColoredBox(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
      ],
    );

    if (widget.fullScreen) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: webView,
          );
        },
      );
    }

    return SizedBox(
      width: screenSize.width,
      height: screenSize.height,
      child: webView,
    );
  }
}
