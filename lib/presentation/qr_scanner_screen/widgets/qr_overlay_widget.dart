import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class QrOverlayWidget extends StatelessWidget {
  final double frameSize;
  final AnimationController scanLineController;

  const QrOverlayWidget({
    super.key,
    required this.frameSize,
    required this.scanLineController,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _OverlayPainter(frameSize: frameSize),
      child: Center(
        child: SizedBox(
          width: frameSize,
          height: frameSize,
          child: Stack(
            children: [
              // Corner brackets
              ..._buildCorners(),
              // Scanning line
              AnimatedBuilder(
                animation: scanLineController,
                builder: (context, _) {
                  final position = scanLineController.value * (frameSize - 4);
                  return Positioned(
                    top: position,
                    left: 12,
                    right: 12,
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            AppTheme.primary.withAlpha(230),
                            AppTheme.primary,
                            AppTheme.primary.withAlpha(230),
                            Colors.transparent,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(1),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withAlpha(128),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCorners() {
    const cornerLength = 28.0;
    const cornerWidth = 4.0;
    const cornerRadius = 3.0;
    const color = Colors.white;

    Widget corner({required bool top, required bool left}) {
      return Positioned(
        top: top ? 0 : null,
        bottom: top ? null : 0,
        left: left ? 0 : null,
        right: left ? null : 0,
        child: SizedBox(
          width: cornerLength,
          height: cornerLength,
          child: CustomPaint(
            painter: _CornerPainter(
              top: top,
              left: left,
              color: color,
              length: cornerLength,
              width: cornerWidth,
              radius: cornerRadius,
            ),
          ),
        ),
      );
    }

    return [
      corner(top: true, left: true),
      corner(top: true, left: false),
      corner(top: false, left: true),
      corner(top: false, left: false),
    ];
  }
}

class _OverlayPainter extends CustomPainter {
  final double frameSize;

  _OverlayPainter({required this.frameSize});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withAlpha(158);
    final cx = size.width / 2;
    final cy = size.height / 2;
    final half = frameSize / 2;

    final outer = Rect.fromLTWH(0, 0, size.width, size.height);
    final inner = RRect.fromRectAndRadius(
      Rect.fromLTRB(cx - half, cy - half, cx + half, cy + half),
      const Radius.circular(16),
    );

    final path = Path()
      ..addRect(outer)
      ..addRRect(inner)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_OverlayPainter oldDelegate) => false;
}

class _CornerPainter extends CustomPainter {
  final bool top;
  final bool left;
  final Color color;
  final double length;
  final double width;
  final double radius;

  const _CornerPainter({
    required this.top,
    required this.left,
    required this.color,
    required this.length,
    required this.width,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    if (top && left) {
      path.moveTo(0, length);
      path.lineTo(0, radius);
      path.arcToPoint(Offset(radius, 0), radius: Radius.circular(radius));
      path.lineTo(length, 0);
    } else if (top && !left) {
      path.moveTo(0, 0);
      path.lineTo(size.width - radius, 0);
      path.arcToPoint(
        Offset(size.width, radius),
        radius: Radius.circular(radius),
      );
      path.lineTo(size.width, length);
    } else if (!top && left) {
      path.moveTo(0, 0);
      path.lineTo(0, size.height - radius);
      path.arcToPoint(
        Offset(radius, size.height),
        radius: Radius.circular(radius),
      );
      path.lineTo(length, size.height);
    } else {
      path.moveTo(0, size.height);
      path.lineTo(size.width - radius, size.height);
      path.arcToPoint(
        Offset(size.width, size.height - radius),
        radius: Radius.circular(radius),
      );
      path.lineTo(size.width, 0);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => false;
}
