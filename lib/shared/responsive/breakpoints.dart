import 'package:flutter/widgets.dart';

class AppBreakpoints {
  static const double mobile = 600.0;
  static const double tablet = 900.0;
  static const double desktop = 1200.0;
  static const double wide = 1600.0;
}

enum ScreenType { mobile, tablet, desktop, wide }

ScreenType screenTypeForWidth(double width) {
  if (width < AppBreakpoints.tablet) return ScreenType.mobile;
  if (width < AppBreakpoints.desktop) return ScreenType.tablet;
  if (width < AppBreakpoints.wide) return ScreenType.desktop;
  return ScreenType.wide;
}

ScreenType screenTypeForContext(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  return screenTypeForWidth(w);
}
