import 'package:flutter/material.dart';

import '../../../core/app_export.dart';

String _coordinatesDisplay(String coordinates) {
  final trimmed = coordinates.trim();
  if (trimmed.isEmpty || trimmed == '—' || trimmed == 'N/A') {
    return 'N/A';
  }
  final parts = trimmed.split(',');
  if (parts.length != 2) return trimmed;
  final lat = double.tryParse(parts[0].trim());
  final lon = double.tryParse(parts[1].trim());
  if (lat == null || lon == null) return trimmed;
  return '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';
}

class UnifiedDashboardCardWidget extends StatelessWidget {
  // Device info
  final String deviceId;
  final String agencyCode;
  final String coordinates;

  // Agency info
  final String agencyName;
  final VoidCallback onRefreshGps;
  final VoidCallback onManualEmit;
  final bool isEmitting;

  // Tracking status
  final bool isOnline;
  final bool isMoving;
  final String lastEmit;

  const UnifiedDashboardCardWidget({
    super.key,
    required this.deviceId,
    required this.agencyCode,
    required this.coordinates,
    required this.agencyName,
    required this.onRefreshGps,
    required this.onManualEmit,
    required this.isEmitting,
    required this.isOnline,
    required this.isMoving,
    required this.lastEmit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(100),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withAlpha(20),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Top Row: Agency Name + Action Buttons ──────────────────
          _AgencyRow(
            agencyName: agencyName,
            agencyCode: agencyCode,
            onRefreshGps: onRefreshGps,
            onManualEmit: onManualEmit,
            isEmitting: isEmitting,
            coordinates: coordinates,
          ),

          // ── Bottom Bar: GPS + Status + Speed ───────────────────────
          _StatusBar(
            coordinates: coordinates,
            isOnline: isOnline,
            isMoving: isMoving,
            lastEmit: lastEmit,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top Row — Agency Name + Action Buttons
// ─────────────────────────────────────────────────────────────────────────────
class _AgencyRow extends StatelessWidget {
  final String agencyName;
  final String agencyCode;
  final String coordinates;
  final VoidCallback onRefreshGps;
  final VoidCallback onManualEmit;
  final bool isEmitting;

  const _AgencyRow({
    required this.agencyName,
    required this.agencyCode,
    required this.coordinates,
    required this.onRefreshGps,
    required this.onManualEmit,
    required this.isEmitting,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Row(
        children: [
          // Agency name — bold, prominent
          // Expanded(
          //   // child: Text(
          //   //   agencyName.isNotEmpty ? agencyName : '—',
          //   //   style: theme.textTheme.titleMedium?.copyWith(
          //   //     fontSize: 14,
          //   //     fontWeight: FontWeight.w800,
          //   //     letterSpacing: 0.3,
          //   //     color: theme.colorScheme.onSurface,
          //   //   ),
          //   //   maxLines: 1,
          //   //   overflow: TextOverflow.ellipsis,
          //   // ),
          //   // child: Row(
          //   //   children: [
          //   //     // GO logo — transparent background
          //   //     // SizedBox(width: 36, height: 36, child: SizedBox()),
          //   //     // const SizedBox(width: 10),
          //   //     Column(
          //   //       crossAxisAlignment: CrossAxisAlignment.start,
          //   //       children: [
          //   //         Text(
          //   //           _deviceName.toUpperCase(),
          //   //           style: theme.textTheme.titleLarge?.copyWith(
          //   //             fontWeight: FontWeight.w700,
          //   //           ),
          //   //         ),
          //   //         Text(
          //   //           _deviceId,
          //   //           style: theme.textTheme.labelSmall?.copyWith(
          //   //             color: theme.colorScheme.onSurfaceVariant,
          //   //           ),
          //   //         ),
          //   //       ],
          //   //     ),
          //   //   ],
          //   // ),
          //   child: Column(
          //     crossAxisAlignment: CrossAxisAlignment.start,
          //     children: [
          //       Text(
          //         agencyName.isNotEmpty ? agencyName : '—',
          //         style: theme.textTheme.titleLarge?.copyWith(
          //           fontWeight: FontWeight.w700,
          //         ),
          //       ),
          //       const SizedBox(height: 4),
          //       Text(
          //         agencyCode.isNotEmpty ? agencyCode.toUpperCase() : '-',
          //         style: theme.textTheme.labelSmall?.copyWith(
          //           color: theme.colorScheme.onSurfaceVariant,
          //           fontSize: 9,
          //         ),
          //       ),
          //     ],
          //   ),
          // ),
          // GPS coordinates
          CustomIconWidget(
            iconName: 'location_on',
            color: const Color.fromARGB(179, 7, 7, 7),
            size: 20,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              coordinates,
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
                color: theme.colorScheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // GPS Refresh button
          _CircleActionButton(
            iconName: 'gps_fixed',
            tooltip: 'Refresh GPS',
            onTap: onRefreshGps,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          // Manual Emit button
          _CircleActionButton(
            iconName: 'send',
            tooltip: 'Manual Emit',
            onTap: isEmitting ? null : onManualEmit,
            color: theme.colorScheme.onSurfaceVariant,
            isLoading: isEmitting,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom Status Bar — dark slim bar
// ─────────────────────────────────────────────────────────────────────────────
class _StatusBar extends StatelessWidget {
  final String coordinates;
  final bool isOnline;
  final bool isMoving;
  final String lastEmit;

  const _StatusBar({
    required this.coordinates,
    required this.isOnline,
    required this.isMoving,
    required this.lastEmit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final motionLabel = isMoving ? 'MOVING' : 'IDLE';
    final connectionLabel = isOnline ? 'ONLINE' : 'OFFLINE';
    final connectionColor = isOnline ? AppTheme.success : AppTheme.errorColor;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(12.0),
          bottomRight: Radius.circular(12.0),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      // Zoom out: kecilkan kandungan automatik kalau tak cukup ruang.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min, // penting dalam FittedBox
          children: [
            // // GPS coordinates
            // CustomIconWidget(
            //   iconName: 'location_on',
            //   color: Colors.white70,
            //   size: 12,
            // ),
            // const SizedBox(width: 4),
            // Text(
            //   _coordinatesDisplay(coordinates),
            //   style: theme.textTheme.labelSmall?.copyWith(
            //     color: Colors.white,
            //     fontSize: 9,
            //     fontWeight: FontWeight.w500,
            //     fontFeatures: [FontFeature.tabularFigures()],
            //   ),
            // ),
            // const SizedBox(width: 14),
            // Connection dot + label
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: connectionColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${connectionLabel.toUpperCase()} · ${motionLabel.toUpperCase()}',
              textAlign: TextAlign.left,
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.white70,
                fontSize: 8,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(width: 34),
            // Speed / last emit
            CustomIconWidget(iconName: 'speed', color: Colors.white54, size: 14),
            const SizedBox(width: 4),
            Text(
              lastEmit.isNotEmpty ? lastEmit : 'N/A · 0 km/h',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared: Circle Action Button
// ─────────────────────────────────────────────────────────────────────────────
class _CircleActionButton extends StatelessWidget {
  final String iconName;
  final String tooltip;
  final VoidCallback? onTap;
  final Color color;
  final bool isLoading;

  const _CircleActionButton({
    required this.iconName,
    required this.tooltip,
    required this.onTap,
    required this.color,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20.0),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Center(
            child: isLoading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                : CustomIconWidget(iconName: iconName, color: color, size: 18),
          ),
        ),
      ),
    );
  }
}
