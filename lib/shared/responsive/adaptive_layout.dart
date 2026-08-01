import 'package:flutter/material.dart';
import 'breakpoints.dart';

class AdaptiveLayout extends StatelessWidget {
  final Widget? navigationRail; // desktop only (not used for tablet)
  final Widget? sidePanel; // tablet/desktop: conversation/history panel
  final Widget body; // main content
  final double tabletSideWidth;
  final double desktopNavWidth;
  final double desktopSideWidth;

  const AdaptiveLayout({
    super.key,
    this.navigationRail,
    this.sidePanel,
    required this.body,
    this.tabletSideWidth = 300,
    this.desktopNavWidth = 80,
    this.desktopSideWidth = 320,
  });

  @override
  Widget build(BuildContext context) {
    final type = screenTypeForContext(context);

    switch (type) {
      case ScreenType.mobile:
        return body;
      case ScreenType.tablet:
        return Row(
          children: [
            if (sidePanel != null)
              SizedBox(width: tabletSideWidth, child: sidePanel),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        );
      case ScreenType.desktop:
      case ScreenType.wide:
        // Basic 3-column skeleton; desktop specific tuning can come later.
        return Row(
          children: [
            if (navigationRail != null)
              SizedBox(width: desktopNavWidth, child: navigationRail),
            if (sidePanel != null) ...[
              SizedBox(width: desktopSideWidth, child: sidePanel),
              const VerticalDivider(width: 1),
            ],
            Expanded(child: body),
          ],
        );
    }
  }
}
