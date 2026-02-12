import 'package:flutter/foundation.dart';

import '../../data/local/local_message_store.dart';

enum MessageDensityMode { compact, comfortable, airy }

class UiSettingsController {
  UiSettingsController(this._localStore);

  final LocalMessageStore _localStore;
  final ValueNotifier<MessageDensityMode> densityMode = ValueNotifier<MessageDensityMode>(MessageDensityMode.comfortable);

  Future<void> init() async {
    final raw = await _localStore.getUiSetting('message_density');
    if (raw == null) {
      return;
    }
    densityMode.value = MessageDensityMode.values.firstWhere(
      (it) => it.name == raw,
      orElse: () => MessageDensityMode.comfortable,
    );
  }

  Future<void> setDensityMode(MessageDensityMode mode) async {
    densityMode.value = mode;
    await _localStore.setUiSetting('message_density', mode.name);
  }
}
