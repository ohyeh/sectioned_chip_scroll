import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:sectioned_chip_scroll/src/presentation/sectioned_chip_scroll_style.dart';

/// Shared translucent chrome; high contrast uses a solid surface and border.
class HeaderMaterial extends StatelessWidget {
  /// Creates header material without changing the child semantics.
  const HeaderMaterial({super.key, required this.style, required this.child});

  /// Material values.
  final SectionedChipScrollStyle style;

  /// Header controls.
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final high = MediaQuery.highContrastOf(context);
    final scheme = Theme.of(context).colorScheme;
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: high ? 1 : style.headerOpacity),
        border: high
            ? Border(bottom: BorderSide(color: scheme.onSurface))
            : null,
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
    return ClipRect(
      child: high
          ? surface
          : BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: style.headerBlur,
                sigmaY: style.headerBlur,
              ),
              child: surface,
            ),
    );
  }
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

/// Keeps title tracking proportional to scaled text; Flutter only scales font size.
TextStyle scaledTitleStyle(BuildContext context, TextStyle style) {
  final size = style.fontSize ?? 16;
  return style.copyWith(
    letterSpacing:
        (style.letterSpacing ?? 0) *
        MediaQuery.textScalerOf(context).scale(size) /
        size,
  );
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

/// Height of one chip row at the current scale, before body padding.
double chipMinimumHeight(
  BuildContext context,
  SectionedChipScrollStyle style, {
  TextStyle? textStyle,
  TextStyle? selectedTextStyle,
}) {
  var height = style.chipMinHeight;
  for (final selected in [false, true]) {
    final painter = TextPainter(
      text: TextSpan(
        text: 'M',
        style: chipLabelStyle(
          Theme.of(context),
          selected: selected,
          textStyle: textStyle,
          selectedTextStyle: selectedTextStyle,
        ),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    height = math.max(
      height,
      painter.height +
          style.chipPadding.resolve(Directionality.of(context)).vertical,
    );
    painter.dispose();
  }
  return height;
}
