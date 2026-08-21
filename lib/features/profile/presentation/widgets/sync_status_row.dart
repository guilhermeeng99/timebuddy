import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/widgets/app_icon.dart';
import 'package:timebuddy/core/extensions/context_extensions.dart';
import 'package:timebuddy/core/sync/sync_service.dart';
import 'package:timebuddy/gen/i18n/strings.g.dart';

/// The passive sync indicator: one icon and one sentence, never anything more.
///
/// **This widget is the entire channel a failed remote write has to the user**
/// (docs/specs/sync.md rule 4). No dialog, no red screen, no retry button: the
/// user reordered two cities, and a modal about Firestore is noise on top of a
/// clock they are trying to read. Local storage already holds their change and
/// the dirty flag already schedules the upload, so there is nothing for them
/// to do and nothing to interrupt them for.
///
/// That is also why [SyncStatus.error] renders in the *warning* token rather
/// than in `error`: red is the app's colour for something the user must fix,
/// and this is not that.
///
/// The service arrives as a parameter rather than through the locator, so the
/// profile page and the sidebar can both host one and a test can drive it from
/// a plain stream.
///
/// ```dart
/// SyncStatusRow(syncService: sl<SyncService>());
/// ```
class SyncStatusRow extends StatefulWidget {
  const SyncStatusRow({required this.syncService, super.key});

  /// Read for [SyncService.status] only. This row never starts a sync: it
  /// reports, and rule 9 says nothing about a settings screen triggers one.
  final SyncService syncService;

  @override
  State<SyncStatusRow> createState() => _SyncStatusRowState();
}

class _SyncStatusRowState extends State<SyncStatusRow> {
  static const double _leadingSize = 20;
  static const double _spinnerStroke = 2;

  /// Resolved once, here, rather than inline in `build`.
  ///
  /// `SyncService.status` is a getter that builds a fresh stream per call (it
  /// replays the last status before the live events), so a `StreamBuilder` fed
  /// straight from `widget.syncService.status` would tear down and resubscribe
  /// on every rebuild — and replay that stale status as if it were new.
  ///
  /// Read once and never re-read, which assumes the service outlives the row:
  /// it is a singleton, and the app deliberately has exactly one (sync.md).
  late final Stream<SyncStatus> _status = widget.syncService.status;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncStatus>(
      stream: _status,
      // The replayed value lands a microtask after `listen`, which is one
      // frame too late: without a seed the row would render blank on mount and
      // then pop into place.
      initialData: SyncStatus.idle,
      builder: (context, snapshot) {
        final status = snapshot.data ?? SyncStatus.idle;
        return Row(
          children: [
            SizedBox(
              width: _leadingSize,
              height: _leadingSize,
              child: _leadingFor(context, status),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                _messageFor(status),
                style: context.textTheme.bodyMedium?.copyWith(
                  color: context.appColors.onBackgroundLight,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _leadingFor(BuildContext context, SyncStatus status) {
    final colors = context.appColors;
    if (status == SyncStatus.syncing) {
      return CircularProgressIndicator(
        strokeWidth: _spinnerStroke,
        color: colors.primaryGlyph,
      );
    }
    return AppIcon(
      _iconFor(status),
      size: _leadingSize,
      color: switch (status) {
        SyncStatus.idle => colors.successInk,
        // Muted, not red: being offline is a fact about the network, and the
        // user's cities are safe on the device either way (rule 1).
        SyncStatus.offline => colors.onBackgroundLight,
        SyncStatus.error => colors.warningInk,
        SyncStatus.syncing => colors.primaryGlyph,
      },
    );
  }

  FaIconData _iconFor(SyncStatus status) => switch (status) {
    SyncStatus.idle => FontAwesomeIcons.circleCheck,
    SyncStatus.offline => FontAwesomeIcons.linkSlash,
    SyncStatus.error => FontAwesomeIcons.triangleExclamation,
    // Unreachable while the spinner stands in for the icon, and kept so the
    // switch stays exhaustive if that ever changes.
    SyncStatus.syncing => FontAwesomeIcons.arrowsRotate,
  };

  /// The copy says what it means for the *user*, not what happened to the
  /// request: "your changes are saved on this device" rather than "write
  /// failed". Both offline strings promise the same thing, because both are
  /// the same promise (sync.md rule 1).
  String _messageFor(SyncStatus status) => switch (status) {
    SyncStatus.idle => t.profile.syncStatusIdle,
    SyncStatus.syncing => t.profile.syncStatusSyncing,
    SyncStatus.offline => t.profile.syncStatusOffline,
    SyncStatus.error => t.profile.syncStatusError,
  };
}
