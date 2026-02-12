abstract class PluginRepository {
  Future<List<String>> listInstalledPlugins();
  Future<void> installPlugin(String bundleId);
  Future<void> removePlugin(String bundleId);
}
