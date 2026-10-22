import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:sectioned_chip_scroll/src/presentation/sectioned_chip_scroll_style.dart';

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
