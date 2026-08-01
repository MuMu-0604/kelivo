import 'breakpoints.dart';

class AdaptiveSpacing {
  static double horizontalPadding(ScreenType t) {
    switch (t) {
      case ScreenType.mobile:
        return 16;
      case ScreenType.tablet:
        return 24;
      case ScreenType.desktop:
        return 32;
      case ScreenType.wide:
        return 48;
    }
  }
}
