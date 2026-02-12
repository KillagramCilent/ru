import '../../domain/repositories/plugin_repository.dart';
import 'telegram_gateway.dart';

class PluginRepositoryImpl implements PluginRepository {
  PluginRepositoryImpl(this._gateway);

  final TelegramGateway _gateway;

  final List<String> _installed = ['com.killagram.translate'];

  @override
  Future<void> installPlugin(String bundleId) async {
    _installed.add(bundleId);
  }

  @override
  Future<List<String>> listInstalledPlugins() async {
    return List.unmodifiable(_installed);
  }

  @override
  Future<void> removePlugin(String bundleId) async {
    _installed.remove(bundleId);
  }
}
