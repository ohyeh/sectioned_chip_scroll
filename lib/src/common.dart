import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:sectioned_chip_scroll/src/sectioned_chip_scroll_style.dart';

/// Trigger bounds in the owning Navigator's coordinate space.
Rect pickerAnchor(BuildContext context) {
  final box = context.findRenderObject()! as RenderBox;
  final overlay =
      Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
  return box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
}

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
  required SectionedChipScrollStyle style,
  required ValueGetter<Rect?> anchor,
  double bottomInset = 0,
}) {
  final textScaler = MediaQuery.textScalerOf(context);
  final theme = Theme.of(context);
  final disableAnimations = MediaQuery.disableAnimationsOf(context);
  final highContrast = MediaQuery.highContrastOf(context);
  final instant =
      MediaQuery.disableAnimationsOf(context) ||
      style.pickerTransition == PickerTransition.none;
  return _PickerRoute(
    style: style,
    instant: instant,
    anchor: anchor,
    bottomInset: bottomInset,
    barrierLabel: barrierLabel,
    pageBuilder: (ctx, _, _) {
      final panel = clampTextScale(maxTextScale, Builder(builder: builder));
      return Theme(
        data: theme,
        child: MediaQuery(
          data: MediaQuery.of(ctx).copyWith(
            textScaler: textScaler,
            disableAnimations: disableAnimations,
            highContrast: highContrast,
          ),
          child: panel,
        ),
      );
    },
  );
}

class _PickerRoute extends RawDialogRoute<void> {
  _PickerRoute({
    required this.style,
    required this.instant,
    required ValueGetter<Rect?> anchor,
    required double bottomInset,
    required super.barrierLabel,
    required super.pageBuilder,
  }) : super(
         barrierColor: style.scrimColor.withValues(alpha: style.scrimOpacity),
         barrierDismissible: true,
         transitionDuration: instant
             ? Duration.zero
             : const Duration(milliseconds: 400),
         transitionBuilder: (context, animation, secondary, child) =>
             _LivePickerAnchor(
               anchor: anchor,
               builder: (context, anchor) {
                 final media = MediaQuery.of(context);
                 final top = anchor.top.clamp(0.0, media.size.height);
                 final left = anchor.left.clamp(0.0, media.size.width);
                 final reserved =
                     math.max(
                       bottomInset,
                       math.max(media.viewInsets.bottom, media.padding.bottom),
                     ) +
                     80;
                 return Padding(
                   padding: EdgeInsets.only(
                     top: top,
                     left: left,
                     right: math.max(0, media.size.width - anchor.right),
                     bottom: math.min(reserved, media.size.height - top),
                   ),
                   child: Align(
                     alignment: Alignment.topCenter,
                     child: instant
                         ? child
                         : SizeTransition(
                             key: const ValueKey(
                               'sectioned_chip_scroll.reveal',
                             ),
                             sizeFactor: animation,
                             axisAlignment: -1,
                             child: child,
                           ),
                   ),
                 );
               },
             ),
       );

  final SectionedChipScrollStyle style;
  final bool instant;
  CurvedAnimation? _curve;

  @override
  Animation<double> createAnimation() => _curve = CurvedAnimation(
    parent: super.createAnimation(),
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInOutCubic,
  );

  @override
  void dispose() {
    _curve?.dispose();
    super.dispose();
  }

  @override
  Curve get barrierCurve => Curves.easeInOut;
}

class _LivePickerAnchor extends StatefulWidget {
  const _LivePickerAnchor({required this.anchor, required this.builder});
  final ValueGetter<Rect?> anchor;
  final Widget Function(BuildContext, Rect) builder;

  @override
  State<_LivePickerAnchor> createState() => _LivePickerAnchorState();
}

class _LivePickerAnchorState extends State<_LivePickerAnchor> {
  late Rect _anchor = widget.anchor()!;

  @override
  Widget build(BuildContext context) {
    // The opener lays out after route build on resize; read its new bounds
    // after layout, then rebuild only if those bounds changed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final next = widget.anchor();
      if (next != null && next != _anchor) setState(() => _anchor = next);
    });
    return widget.builder(context, _anchor);
  }
}

/// A scalar spring that retargets from its presentation value and velocity.
class SpringValue extends StatefulWidget {
  /// Creates a spring without a fixed-duration curve.
  const SpringValue({
    super.key,
    required this.value,
    required this.style,
    required this.builder,
    this.response,
  });

  /// Target value.
  final double value;

  /// Physical parameters.
  final SectionedChipScrollStyle style;

  /// Optional press response.
  final double? response;

  /// Internal visual builder; does not expose an app slot.
  final Widget Function(BuildContext, double) builder;
  @override
  State<SpringValue> createState() => _SpringValueState();
}

class _SpringValueState extends State<SpringValue>
    with SingleTickerProviderStateMixin {
  late final _value = AnimationController.unbounded(
    vsync: this,
    value: widget.value,
  );
  void _retarget() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _value.value = widget.value;
    } else {
      _value.animateWith(
        SpringSimulation(
          widget.style.spring(response: widget.response),
          _value.value,
          widget.value,
          _value.velocity,
        ),
      );
    }
  }

  @override
  void didUpdateWidget(covariant SpringValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _retarget();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _value.value = widget.value;
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _value,
    builder: (context, _) => widget.builder(context, _value.value),
  );
}

/// Pointer-down feedback around an existing accessible control.
class PressFeedback extends StatefulWidget {
  /// Keeps commit and keyboard activation on the child control.
  const PressFeedback({super.key, required this.style, required this.child});

  /// Visual and physical values.
  final SectionedChipScrollStyle style;

  /// Existing control with its own tap recognizer and focus node.
  final Widget child;
  @override
  State<PressFeedback> createState() => _PressFeedbackState();
}

class _PressFeedbackState extends State<PressFeedback> {
  Offset? _origin;
  bool _pressed = false;
  void _set(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) {
      _origin = event.position;
      _set(true);
    },
    onPointerMove: (event) {
      if (_origin != null && (event.position - _origin!).distance > 18) {
        _set(false);
      }
    },
    onPointerUp: (_) => _set(false),
    onPointerCancel: (_) => _set(false),
    child: SpringValue(
      value: _pressed ? widget.style.pressScale : 1,
      style: widget.style,
      response: widget.style.pressResponse,
      builder: (context, scale) => Transform.scale(
        scale: scale,
        transformHitTests: false,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.style.cornerRadius),
          child: ColoredBox(
            color: _pressed
                ? widget.style.accentColor.withValues(
                    alpha: widget.style.pressHighlightOpacity,
                  )
                : Colors.transparent,
            child: widget.child,
          ),
        ),
      ),
    ),
  );
}

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

/// Whether [ids] are all non-empty and unique; for asserts.
bool uniqueIds(Iterable<String> ids) {
  final seen = <String>{};
  return ids.every((id) => id.isNotEmpty && seen.add(id));
}

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

/// The shell of a picker: a title, a close button and a scrolling body.
class PickerPanel extends StatefulWidget {
  /// Creates a picker shell.
  const PickerPanel({
    super.key,
    required this.title,
    required this.closeLabel,
    required this.closeIcon,
    required this.child,
    this.titleStyle,
    this.style = const SectionedChipScrollStyle.outlined(),
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

  /// Shared corner and press values.
  final SectionedChipScrollStyle style;

  @override
  State<PickerPanel> createState() => _PickerPanelState();
}

class _PickerPanelState extends State<PickerPanel> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = widget.style;
    return Material(
      key: const ValueKey('sectioned_chip_scroll.panel'),
      color: style.panelBackground ?? theme.colorScheme.surface,
      elevation: style.panelElevation,
      shadowColor: style.panelShadowColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(style.panelBottomRadius),
        ),
        side: MediaQuery.highContrastOf(context)
            ? BorderSide(color: theme.colorScheme.onSurface)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            key: const ValueKey('sectioned_chip_scroll.panelHeader'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.all(12),
                  child: Semantics(
                    header: true,
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: scaledTitleStyle(
                        context,
                        (theme.textTheme.titleMedium ?? const TextStyle())
                            .merge(widget.titleStyle),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 48,
                height: 48,
                child: PressFeedback(
                  style: style,
                  child: IconButton(
                    style: IconButton.styleFrom(
                      splashFactory: NoSplash.splashFactory,
                    ),
                    tooltip: widget.closeLabel,
                    icon: Icon(widget.closeIcon),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ],
          ),
          Flexible(
            child: Stack(
              children: [
                NotificationListener<ScrollMetricsNotification>(
                  onNotification: (_) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() {});
                    });
                    return false;
                  },
                  child: Scrollbar(
                    controller: _scroll,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      key: const ValueKey('sectioned_chip_scroll.panelScroll'),
                      controller: _scroll,
                      padding: const EdgeInsets.all(8),
                      child: widget.child,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: style.edgeFadeExtent,
                  child: IgnorePointer(
                    child: ListenableBuilder(
                      listenable: _scroll,
                      builder: (context, _) => DecoratedBox(
                        key: const ValueKey('sectioned_chip_scroll.panelFade'),
                        decoration: BoxDecoration(
                          gradient:
                              _scroll.hasClients &&
                                  _scroll.position.hasContentDimensions &&
                                  _scroll.position.extentAfter > 0
                              ? LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    (style.panelBackground ??
                                            theme.colorScheme.surface)
                                        .withValues(alpha: 0),
                                    style.panelBackground ??
                                        theme.colorScheme.surface,
                                  ],
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
