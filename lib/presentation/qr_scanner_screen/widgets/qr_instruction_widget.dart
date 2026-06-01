import 'package:flutter/material.dart';

class QrInstructionWidget extends StatelessWidget {
  final double frameSize;

  const QrInstructionWidget({super.key, required this.frameSize});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final centerY = size.height / 2;
    final frameTop = centerY - frameSize / 2;

    return Positioned(
      top: frameTop - 72,
      left: 24,
      right: 24,
      child: Column(
        children: [
          Text(
            'Position QR code within the frame',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'The code will be scanned automatically',
            style: TextStyle(
              color: Colors.white.withAlpha(166),
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
