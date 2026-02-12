class ChatScreenController {
  void Function()? _jumpNextUnread;
  void Function()? _toggleDensityMode;
  void Function()? _openAutomationPanel;
  void Function()? _openInspector;
  void Function()? _markFocusedImportant;
  void Function()? _pinFocusedLocal;

  void bind({
    required void Function() jumpNextUnread,
    required void Function() toggleDensityMode,
    required void Function() openAutomationPanel,
    required void Function() openInspector,
    required void Function() markFocusedImportant,
    required void Function() pinFocusedLocal,
  }) {
    _jumpNextUnread = jumpNextUnread;
    _toggleDensityMode = toggleDensityMode;
    _openAutomationPanel = openAutomationPanel;
    _openInspector = openInspector;
    _markFocusedImportant = markFocusedImportant;
    _pinFocusedLocal = pinFocusedLocal;
  }

  void unbind() {
    _jumpNextUnread = null;
    _toggleDensityMode = null;
    _openAutomationPanel = null;
    _openInspector = null;
    _markFocusedImportant = null;
    _pinFocusedLocal = null;
  }

  void jumpNextUnread() => _jumpNextUnread?.call();
  void toggleDensityMode() => _toggleDensityMode?.call();
  void openAutomationPanel() => _openAutomationPanel?.call();
  void openInspector() => _openInspector?.call();
  void markFocusedImportant() => _markFocusedImportant?.call();
  void pinFocusedLocal() => _pinFocusedLocal?.call();
}
