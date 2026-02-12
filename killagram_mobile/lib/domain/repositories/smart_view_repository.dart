import '../entities/search_result.dart';
import '../entities/smart_view.dart';

abstract class SmartViewRepository {
  Future<List<SmartView>> listViews();
  Future<void> pinView(String viewId, bool pinned);
  Future<void> activateView(String? viewId);
  Future<String?> activeViewId();
  Future<List<SearchResult>> openView(String viewId, {int limit = 120});
  Future<void> saveCustomView(Map<String, dynamic> definition);
  Future<void> deleteCustomView(String viewId);
  Future<void> saveSearchAsSmartView(Map<String, dynamic> searchDefinition);
}
