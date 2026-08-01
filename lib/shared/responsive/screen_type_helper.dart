import 'package:flutter/widgets.dart';
import 'breakpoints.dart';

class ResponsiveHelper {
  static ScreenType screenType(BuildContext context) =>
      screenTypeForContext(context);
  static bool isMobile(BuildContext c) =>
      screenTypeForContext(c) == ScreenType.mobile;
  static bool isTablet(BuildContext c) =>
      screenTypeForContext(c) == ScreenType.tablet;
  static bool isDesktop(BuildContext c) {
    final t = screenTypeForContext(c);
    return t == ScreenType.desktop || t == ScreenType.wide;
  }
}
