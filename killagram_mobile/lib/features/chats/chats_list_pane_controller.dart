class ChatsListPaneController {
  Future<void> Function(String viewId)? _openSmartView;

  void bind({required Future<void> Function(String viewId) openSmartView}) {
    _openSmartView = openSmartView;
  }

  void unbind() {
    _openSmartView = null;
  }

  Future<void> openSmartView(String viewId) async {
    final handler = _openSmartView;
    if (handler == null) return;
    await handler(viewId);
  }
}
