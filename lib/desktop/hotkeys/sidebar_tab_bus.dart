import 'dart:async';

/// Desktop sidebar tabs control bus (Assistants/Topics) for embedded left panel.
class DesktopSidebarTabBus {
  DesktopSidebarTabBus._();
  static final DesktopSidebarTabBus instance = DesktopSidebarTabBus._();

  final _controller = StreamController<int>.broadcast();
  // 0 = Assistants, 1 = Topics
  Stream<int> get stream => _controller.stream;

  int _currentIndex = 0;
  int get currentIndex => _currentIndex;

  void setCurrentIndex(int index) {
    _currentIndex = index;
  }

  void switchToAssistants() => _controller.add(0);
  void switchToTopics() => _controller.add(1);

  void dispose() => _controller.close();
}
