import 'package:flutter/material.dart';
import '../../../widgets/status_badge_widget.dart';

class ProvisioningStatusWidget extends StatelessWidget {
  final bool isProvisioned;
  final bool isOnline;

  const ProvisioningStatusWidget({
    super.key,
    required this.isProvisioned,
    required this.isOnline,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        StatusBadgeWidget(
          status: isProvisioned
              ? BadgeStatus.provisioned
              : BadgeStatus.notProvisioned,
        ),
        const SizedBox(width: 10),
        StatusBadgeWidget(
          status: isOnline ? BadgeStatus.online : BadgeStatus.offline,
          animate: isOnline,
        ),
      ],
    );
  }
}
