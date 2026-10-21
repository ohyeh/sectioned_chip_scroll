import 'dart:math' as math;

import 'package:flutter/material.dart';

/// How a picker enters and leaves its anchored position.
enum PickerTransition {
  /// Instant panel and scrim.
  none,

  /// Opaque panel clipped from the top, with a fading scrim.
  clipReveal,
}

/// Visual values shared by the rail, chips and section headers.
@immutable
class SectionedChipScrollStyle {
  /// The single built-in style: text rail and rectangular outlined chips.
  const SectionedChipScrollStyle.outlined({
    this.accentColor = const Color(0xFF424242),
    this.chipBackground = Colors.transparent,
    this.selectedChipBackground,
    this.selectedChipBorder,
    this.chipMinHeight = 48,
    this.chipPadding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.panelBackground,
    this.panelBottomRadius = 20,
    this.panelShadowColor,
    this.scrimColor = Colors.black,
    this.chipShape = const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(8)),
    ),
    this.chipTextStyle = const TextStyle(letterSpacing: 0, height: 1.25),
    this.selectedChipTextStyle = const TextStyle(fontWeight: FontWeight.w600),
    this.sectionTitleStyle = const TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.36,
      height: 1.2,
    ),
    this.panelTitleStyle = const TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.4,
      height: 1.2,
    ),
    this.categoryTextStyle = const TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.36,
      height: 1.2,
    ),
    this.pickerTransition = PickerTransition.clipReveal,
    this.springResponse = 0.36,
    this.dampingRatio = 1,
    this.pressScale = 0.97,
    this.pressResponse = 0.10,
    this.headerOpacity = 0.9,
    this.headerBlur = 16,
    this.edgeFadeExtent = 16,
    this.cornerRadius = 8,
    this.selectedFillOpacity = 0.06,
    this.pressHighlightOpacity = 0.08,
    this.scrimOpacity = 0.24,
    this.panelElevation = 8,
  }) : assert(chipMinHeight >= 48 && chipMinHeight < double.infinity),
       assert(panelBottomRadius >= 0 && panelBottomRadius < double.infinity),
       assert(springResponse > 0 && springResponse < double.infinity),
       assert(pressResponse > 0 && pressResponse < double.infinity),
       assert(dampingRatio >= 1 && dampingRatio < double.infinity),
       assert(pressScale > 0 && pressScale <= 1),
       assert(headerOpacity >= 0 && headerOpacity <= 1),
       assert(headerBlur >= 0 && headerBlur < double.infinity),
       assert(edgeFadeExtent >= 0 && edgeFadeExtent < double.infinity),
       assert(cornerRadius >= 0 && cornerRadius < double.infinity),
       assert(selectedFillOpacity >= 0 && selectedFillOpacity <= 1),
       assert(pressHighlightOpacity >= 0 && pressHighlightOpacity <= 1),
       assert(scrimOpacity >= 0 && scrimOpacity <= 1),
       assert(panelElevation >= 0 && panelElevation < double.infinity);

  /// Immediate highlight strength on pointer down.
  final double pressHighlightOpacity;

  /// Dim layer opacity behind a picker.
  final double scrimOpacity;

  /// Picker shadow elevation.
  final double panelElevation;

  /// Picker clip animation; reduced motion always uses an instant change.
  final PickerTransition pickerTransition;

  /// Selected fill; null uses the neutral accent tint.
  final Color? selectedChipBackground;

  /// Selected outline; null uses the selected foreground with width 1.
  final BorderSide? selectedChipBorder;

  /// Minimum chip hit height, at least 48 logical pixels.
  final double chipMinHeight;

  /// Space inside each chip.
  final EdgeInsetsGeometry chipPadding;

  /// Panel surface; null uses the theme surface.
  final Color? panelBackground;

  /// Radius of the two bottom panel corners.
  final double panelBottomRadius;

  /// Panel shadow color; null uses the Material default.
  final Color? panelShadowColor;

  /// Scrim tint, combined with [scrimOpacity].
  final Color scrimColor;

  /// Perceptual response in seconds; not a fixed animation duration.
  final double springResponse;

  /// One is critically damped, without menu bounce.
  final double dampingRatio;

  /// Visual scale during a pointer press; hit targets keep their size.
  final double pressScale;

  /// Response for press feedback, in seconds.
  final double pressResponse;

  /// Opacity of the sticky header material.
  final double headerOpacity;

  /// Backdrop blur radius, disabled in high contrast.
  final double headerBlur;

  /// Depth of the scroll-edge fade.
  final double edgeFadeExtent;

  /// Shared corner unit; panels use twice this radius.
  final double cornerRadius;

  /// Accent tint strength for selected chips.
  final double selectedFillOpacity;

  /// Category bar typography.
  final TextStyle categoryTextStyle;

  /// Builds the physical spring used for each motion.
  SpringDescription spring({double? response}) =>
      SpringDescription.withDampingRatio(
        mass: 1,
        stiffness: math
            .pow(2 * math.pi / (response ?? springResponse), 2)
            .toDouble(),
        ratio: dampingRatio,
      );

  /// Selected text color with at least 4.5:1 contrast on [background].
  Color selectedForeground(Color background) {
    final a = accentColor.computeLuminance();
    final b = background.computeLuminance();
    if ((math.max(a, b) + 0.05) / (math.min(a, b) + 0.05) >= 4.5) {
      return accentColor;
    }
    return b > 0.179 ? Colors.black : Colors.white;
  }

  /// Selected rail text and chip outline color.
  final Color accentColor;

  /// Background of each chip.
  final Color chipBackground;

  /// Chip shape; selection supplies the outline.
  final OutlinedBorder chipShape;

  /// Unselected label style.
  final TextStyle? chipTextStyle;

  /// Selected label style.
  final TextStyle? selectedChipTextStyle;

  /// Section header style.
  final TextStyle? sectionTitleStyle;

  /// Picker title style.
  final TextStyle? panelTitleStyle;

  /// Copies these values with the supplied changes.
  SectionedChipScrollStyle copyWith({
    Color? accentColor,
    Color? chipBackground,
    Color? selectedChipBackground,
    BorderSide? selectedChipBorder,
    double? chipMinHeight,
    EdgeInsetsGeometry? chipPadding,
    Color? panelBackground,
    double? panelBottomRadius,
    Color? panelShadowColor,
    Color? scrimColor,
    OutlinedBorder? chipShape,
    TextStyle? chipTextStyle,
    TextStyle? selectedChipTextStyle,
    TextStyle? sectionTitleStyle,
    TextStyle? panelTitleStyle,
    TextStyle? categoryTextStyle,
    PickerTransition? pickerTransition,
    double? springResponse,
    double? dampingRatio,
    double? pressScale,
    double? pressResponse,
    double? headerOpacity,
    double? headerBlur,
    double? edgeFadeExtent,
    double? cornerRadius,
    double? selectedFillOpacity,
    double? pressHighlightOpacity,
    double? scrimOpacity,
    double? panelElevation,
  }) => SectionedChipScrollStyle.outlined(
    accentColor: accentColor ?? this.accentColor,
    chipBackground: chipBackground ?? this.chipBackground,
    selectedChipBackground:
        selectedChipBackground ?? this.selectedChipBackground,
    selectedChipBorder: selectedChipBorder ?? this.selectedChipBorder,
    chipMinHeight: chipMinHeight ?? this.chipMinHeight,
    chipPadding: chipPadding ?? this.chipPadding,
    panelBackground: panelBackground ?? this.panelBackground,
    panelBottomRadius: panelBottomRadius ?? this.panelBottomRadius,
    panelShadowColor: panelShadowColor ?? this.panelShadowColor,
    scrimColor: scrimColor ?? this.scrimColor,
    chipShape: chipShape ?? this.chipShape,
    chipTextStyle: chipTextStyle ?? this.chipTextStyle,
    selectedChipTextStyle: selectedChipTextStyle ?? this.selectedChipTextStyle,
    sectionTitleStyle: sectionTitleStyle ?? this.sectionTitleStyle,
    panelTitleStyle: panelTitleStyle ?? this.panelTitleStyle,
    categoryTextStyle: categoryTextStyle ?? this.categoryTextStyle,
    pickerTransition: pickerTransition ?? this.pickerTransition,
    springResponse: springResponse ?? this.springResponse,
    dampingRatio: dampingRatio ?? this.dampingRatio,
    pressScale: pressScale ?? this.pressScale,
    pressResponse: pressResponse ?? this.pressResponse,
    headerOpacity: headerOpacity ?? this.headerOpacity,
    headerBlur: headerBlur ?? this.headerBlur,
    edgeFadeExtent: edgeFadeExtent ?? this.edgeFadeExtent,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    selectedFillOpacity: selectedFillOpacity ?? this.selectedFillOpacity,
    pressHighlightOpacity: pressHighlightOpacity ?? this.pressHighlightOpacity,
    scrimOpacity: scrimOpacity ?? this.scrimOpacity,
    panelElevation: panelElevation ?? this.panelElevation,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SectionedChipScrollStyle &&
          other.accentColor == accentColor &&
          other.chipBackground == chipBackground &&
          other.selectedChipBackground == selectedChipBackground &&
          other.selectedChipBorder == selectedChipBorder &&
          other.chipMinHeight == chipMinHeight &&
          other.chipPadding == chipPadding &&
          other.panelBackground == panelBackground &&
          other.panelBottomRadius == panelBottomRadius &&
          other.panelShadowColor == panelShadowColor &&
          other.scrimColor == scrimColor &&
          other.chipShape == chipShape &&
          other.chipTextStyle == chipTextStyle &&
          other.selectedChipTextStyle == selectedChipTextStyle &&
          other.sectionTitleStyle == sectionTitleStyle &&
          other.panelTitleStyle == panelTitleStyle &&
          other.categoryTextStyle == categoryTextStyle &&
          other.pickerTransition == pickerTransition &&
          other.springResponse == springResponse &&
          other.dampingRatio == dampingRatio &&
          other.pressScale == pressScale &&
          other.pressResponse == pressResponse &&
          other.headerOpacity == headerOpacity &&
          other.headerBlur == headerBlur &&
          other.edgeFadeExtent == edgeFadeExtent &&
          other.cornerRadius == cornerRadius &&
          other.selectedFillOpacity == selectedFillOpacity &&
          other.pressHighlightOpacity == pressHighlightOpacity &&
          other.scrimOpacity == scrimOpacity &&
          other.panelElevation == panelElevation;

  @override
  int get hashCode => Object.hashAll([
    accentColor,
    chipBackground,
    selectedChipBackground,
    selectedChipBorder,
    chipMinHeight,
    chipPadding,
    panelBackground,
    panelBottomRadius,
    panelShadowColor,
    scrimColor,
    chipShape,
    chipTextStyle,
    selectedChipTextStyle,
    sectionTitleStyle,
    panelTitleStyle,
    categoryTextStyle,
    pickerTransition,
    springResponse,
    dampingRatio,
    pressScale,
    pressResponse,
    headerOpacity,
    headerBlur,
    edgeFadeExtent,
    cornerRadius,
    selectedFillOpacity,
    pressHighlightOpacity,
    scrimOpacity,
    panelElevation,
  ]);
}
