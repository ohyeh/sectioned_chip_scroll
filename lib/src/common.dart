import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// A modal picker route that keeps the text scale and theme of [context].
///
/// The route sits under the Navigator, which does not see a local
/// `MediaQuery` or `Theme` of the opener. The text scale and theme are
/// carried over; the route keeps its own size, padding and insets so
/// rotation still works. [maxTextScale] is applied again inside.
RawDialogRoute<void> pickerRoute(
  BuildContext context, {
  required String barrierLabel,
  required double? maxTextScale,
  required WidgetBuilder builder,
}) {
  final textScaler = MediaQuery.textScalerOf(context);
  final theme = Theme.of(context);
  return RawDialogRoute<void>(
    barrierDismissible: true,
    barrierLabel: barrierLabel,
    barrierColor: Colors.black54,
    pageBuilder: (ctx, _, _) {
      final panel = clampTextScale(maxTextScale, Builder(builder: builder));
      return Theme(
        data: theme,
        child: MediaQuery(
          data: MediaQuery.of(ctx).copyWith(textScaler: textScaler),
          child: panel,
        ),
      );
    },
  );
}

/// Sends [message] as a screen reader announcement when the platform
/// supports announcements.
void announce(BuildContext context, String message) {
  if (!MediaQuery.supportsAnnounceOf(context)) return;
  SemanticsService.sendAnnouncement(
    View.of(context),
    message,
    Directionality.of(context),
  );
}

/// Wraps [child] in a text scale clamp when [max] is not null.
Widget clampTextScale(double? max, Widget child) => max == null
    ? child
    : MediaQuery.withClampedTextScaling(maxScaleFactor: max, child: child);

/// Whether [ids] are all non-empty and unique; for asserts.
bool uniqueIds(Iterable<String> ids) {
  final seen = <String>{};
  return ids.every((id) => id.isNotEmpty && seen.add(id));
}

/// Label style of a chip or a category tab, merged over `labelLarge`.
TextStyle chipLabelStyle(
  ThemeData theme, {
  required bool selected,
  TextStyle? textStyle,
  TextStyle? selectedTextStyle,
}) {
  final scheme = theme.colorScheme;
  final base = (theme.textTheme.labelLarge ?? const TextStyle())
      .copyWith(color: scheme.onSurface)
      .merge(textStyle);
  return selected
      ? base
            .copyWith(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            )
            .merge(selectedTextStyle)
      : base;
}

/// The shell of a picker: a title, a close button and a scrolling body.
class PickerPanel extends StatelessWidget {
  /// Creates a picker shell.
  const PickerPanel({
    super.key,
    required this.title,
    required this.closeLabel,
    required this.closeIcon,
    required this.child,
    this.titleStyle,
  });

  /// Picker title, read as a header.
  final String title;

  /// Tooltip and screen reader label of the close button.
  final String closeLabel;

  /// Icon of the close button.
  final IconData closeIcon;

  /// Picker body.
  final Widget child;

  /// Merged over `textTheme.titleMedium`.
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Material(
          color: theme.colorScheme.surface,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.all(12),
                      child: Semantics(
                        header: true,
                        child: Text(
                          title,
                          style:
                              (theme.textTheme.titleMedium ?? const TextStyle())
                                  .merge(titleStyle),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: closeLabel,
                    icon: Icon(closeIcon),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
