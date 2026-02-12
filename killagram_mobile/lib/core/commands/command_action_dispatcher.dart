class CommandActionDispatcher {
  Future<void> dispatch(Future<void> Function() action) async {
    await action();
  }
}
