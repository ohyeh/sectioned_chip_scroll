import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:sectioned_chip_scroll/src/presentation/chrome.dart';
import 'package:sectioned_chip_scroll/src/presentation/motion.dart';
import 'package:sectioned_chip_scroll/src/presentation/sectioned_chip_scroll_style.dart';

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
  const PickerChevron(super.icon, {super.key, super.color});

  @override
  Widget build(BuildContext context) {
    final scale = pickerChevronScale(context);
    return Center(
      widthFactor: 1,
      heightFactor: 1,
      child: CustomPaint(
        size: Size(16 * scale, 8 * scale),
        painter: _PickerChevronPainter(
          icon == Icons.expand_less,
          color ?? const Color(0xFF2C2A2D),
        ),
      ),
    );
  }
}

class _PickerChevronPainter extends CustomPainter {
  const _PickerChevronPainter(this.up, this.color);
  final bool up;
  final Color color;

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
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PickerChevronPainter oldDelegate) =>
      up != oldDelegate.up || color != oldDelegate.color;
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
        final painter =
            TextPainter(
              text: TextSpan(text: widget.title, style: titleStyle),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
              maxLines: 1,
            )..layout(
              maxWidth: math.max(
                0,
                box.maxWidth - widget.buttonSize.width - 24,
              ),
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
                    icon: PickerChevron(
                      widget.closeIcon,
                      color: style.pickerChevronColor,
                    ),
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
