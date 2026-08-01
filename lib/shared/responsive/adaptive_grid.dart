import 'breakpoints.dart';

class AdaptiveGrid {
  static int columns(ScreenType t, {int mobileColumns = 1}) {
    switch (t) {
      case ScreenType.mobile:
        return mobileColumns;
      case ScreenType.tablet:
        return mobileColumns * 2;
      case ScreenType.desktop:
        return mobileColumns * 3;
      case ScreenType.wide:
        return mobileColumns * 4;
    }
  }
}
