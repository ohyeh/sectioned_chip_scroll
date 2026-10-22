import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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
                 final reserved = math.max(
                   bottomInset,
                   math.max(media.viewInsets.bottom, media.padding.bottom),
                 );
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

  void _checkAnchor(Duration _) {
    if (!mounted) return;
    final anchor = widget.anchor();
    if (anchor != null && anchor != _anchor) {
      setState(() => _anchor = anchor);
    }
    WidgetsBinding.instance.addPostFrameCallback(_checkAnchor);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_checkAnchor);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, _) {
      // The opener has its new bounds during layout, before this frame paints.
      _anchor = widget.anchor() ?? _anchor;
      return widget.builder(context, _anchor);
    },
  );
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

/// Scale of the board chevron, independent of the label's maximum size.
double pickerChevronScale(BuildContext context) =>
    (MediaQuery.textScalerOf(context).scale(16) / 16).clamp(0.0, 2.0);

/// Shared end slot for a picker trigger and its close button.
Size pickerButtonSize(BuildContext context, double rowHeight) => Size(
  math.max(48, 16 * pickerChevronScale(context) + 24),
  math.max(48, rowHeight),
);

/// Plain picker controls keep their existing focus and press feedback.
final plainPickerButtonStyle = IconButton.styleFrom(
  backgroundColor: Colors.transparent,
  side: BorderSide.none,
  padding: EdgeInsets.zero,
  minimumSize: const Size(48, 48),
  splashFactory: NoSplash.splashFactory,
);

/// An icon identifier with the board's vector instead of a font glyph.
class PickerChevron extends Icon {
  /// Draws the expand or collapse chevron.
  const PickerChevron(super.icon, {super.key});

  @override
  Widget build(BuildContext context) {
    final scale = pickerChevronScale(context);
    return Center(
      widthFactor: 1,
      heightFactor: 1,
      child: CustomPaint(
        size: Size(16 * scale, 8 * scale),
        painter: _PickerChevronPainter(icon == Icons.expand_less),
      ),
    );
  }
}

class _PickerChevronPainter extends CustomPainter {
  const _PickerChevronPainter(this.up);
  final bool up;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 16, size.height / 8);
    final path = Path()
      ..moveTo(1, up ? 7 : 1)
      ..lineTo(8, up ? 1 : 7)
      ..lineTo(15, up ? 7 : 1);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF2C2A2D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PickerChevronPainter oldDelegate) => up != oldDelegate.up;
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
    required this.minimumBodyHeight,
    required this.buttonSize,
    this.triggerRowHeight,
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

  /// Height of one chip row, including the body padding.
  final double minimumBodyHeight;

  /// Same end slot as the trigger, independent of the panel title height.
  final Size buttonSize;

  /// Section bar height when the close button must occupy the trigger's slot.
  final double? triggerRowHeight;

  /// Merged over `textTheme.titleMedium`.
  final TextStyle? titleStyle;

  /// Shared corner and press values.
  final SectionedChipScrollStyle style;

  @override
  State<PickerPanel> createState() => _PickerPanelState();
}

class _PickerScrollController extends ScrollController {
  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _PickerScrollPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
  );
}

class _PickerScrollPosition extends ScrollPositionWithSingleContext {
  _PickerScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
  });

  @override
  bool get shouldIgnorePointer {
    final current = activity;
    final slop = computeHitSlop(
      ui.PointerDeviceKind.touch,
      MediaQuery.maybeGestureSettingsOf(context.storageContext),
    );
    // Below one touch slop per 60Hz frame, a tap should pick rather than stop.
    if (current is BallisticScrollActivity &&
        current.velocity.abs() < slop * 60) {
      return false;
    }
    return super.shouldIgnorePointer;
  }

  @override
  double setPixels(double newPixels) {
    final overscroll = super.setPixels(newPixels);
    if (activity is BallisticScrollActivity) {
      context.setIgnorePointer(shouldIgnorePointer);
    }
    return overscroll;
  }
}

class _PickerPanelState extends State<PickerPanel> {
  final _scroll = _PickerScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = widget.style;
    return LayoutBuilder(
      builder: (context, box) {
        final titleStyle = scaledTitleStyle(
          context,
          (theme.textTheme.titleMedium ?? const TextStyle()).merge(
            widget.titleStyle,
          ),
        );
        final painter = TextPainter(
          text: TextSpan(text: widget.title, style: titleStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout(
          maxWidth: math.max(0, box.maxWidth - widget.buttonSize.width - 24),
        );
        final headerHeight =
            widget.triggerRowHeight ??
            math.max(widget.buttonSize.height, painter.height + 24);
        painter.dispose();
        final minimumHeight = headerHeight + widget.minimumBodyHeight;
        final reserve = math.min(
          80.0,
          math.max(0.0, box.maxHeight - minimumHeight),
        );
        final height = box.maxHeight - reserve;
        final scrollHeader = height < minimumHeight;
        final header = SizedBox(
          height: headerHeight,
          child: Row(
            key: const ValueKey('sectioned_chip_scroll.panelHeader'),
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: 12,
                  ),
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
                width: widget.buttonSize.width,
                height: widget.buttonSize.height,
                child: PressFeedback(
                  style: style,
                  child: IconButton(
                    style: plainPickerButtonStyle,
                    iconSize: 16 * pickerChevronScale(context),
                    tooltip: widget.closeLabel,
                    icon: PickerChevron(widget.closeIcon),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ],
          ),
        );
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: height),
          child: Material(
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
                if (!scrollHeader) header,
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
                            key: const ValueKey(
                              'sectioned_chip_scroll.panelScroll',
                            ),
                            controller: _scroll,
                            padding: scrollHeader
                                ? EdgeInsets.zero
                                : const EdgeInsets.all(8),
                            child: scrollHeader
                                ? Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      header,
                                      Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: widget.child,
                                      ),
                                    ],
                                  )
                                : widget.child,
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
                              key: const ValueKey(
                                'sectioned_chip_scroll.panelFade',
                              ),
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
          ),
        );
      },
    );
  }
}
