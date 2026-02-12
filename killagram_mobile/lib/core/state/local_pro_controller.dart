import 'package:flutter/foundation.dart';

import '../../data/local/local_message_store.dart';

class LocalProController {
  LocalProController(this._store);

  final LocalMessageStore _store;

  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);
  final ValueNotifier<String> userLocalEmoji = ValueNotifier<String>('');

  Future<void> init() async {
    enabled.value = await _store.getLocalProEnabled();
    userLocalEmoji.value = await _store.getUserLocalEmoji();
  }

  Future<void> setEnabled(bool value) async {
    enabled.value = value;
    await _store.setLocalProEnabled(value);
  }

  Future<void> setUserLocalEmoji(String value) async {
    userLocalEmoji.value = value;
    await _store.setUserLocalEmoji(value);
  }
}
