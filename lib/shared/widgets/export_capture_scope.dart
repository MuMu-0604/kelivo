import 'package:flutter/widgets.dart';

class ExportCaptureScope extends InheritedWidget {
  final bool enabled;
  const ExportCaptureScope({
    super.key,
    required this.enabled,
    required super.child,
  });

  static bool of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ExportCaptureScope>();
    return scope?.enabled ?? false;
  }

  @override
  bool updateShouldNotify(covariant ExportCaptureScope oldWidget) =>
      oldWidget.enabled != enabled;
}
