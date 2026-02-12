import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import '../../data/telegram/api_client.dart';
import '../../data/telegram/auth_repository_impl.dart';
import '../../data/telegram/account_repository_impl.dart';
import '../../data/telegram/auth_storage.dart';
import '../../data/telegram/telegram_gateway.dart';
import '../../data/telegram/telegram_gateway_impl.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/account_repository.dart';
import '../../domain/repositories/chat_repository.dart';
import '../../data/telegram/chat_repository_impl.dart';
import '../../domain/repositories/ai_repository.dart';
import '../../data/telegram/ai_repository_impl.dart';
import '../../domain/repositories/plugin_repository.dart';
import '../../data/telegram/plugin_repository_impl.dart';
import '../../domain/repositories/folder_repository.dart';
import '../../data/telegram/folder_repository_impl.dart';
import '../../domain/repositories/search_repository.dart';
import '../../domain/repositories/smart_view_repository.dart';
import '../../domain/repositories/workspace_repository.dart';
import '../../data/telegram/search_repository_impl.dart';
import '../../data/local/smart_view_repository_impl.dart';
import '../../data/local/local_message_store.dart';
import '../../data/local/local_workspace_store.dart';
import '../../data/local/workspace_repository_impl.dart';
import '../state/ui_settings_controller.dart';
import '../state/local_pro_controller.dart';
import '../ai/ai_service.dart';
import '../ai/ai_service_impl.dart';
import '../ai/ai_provider_type.dart';
import '../ai/providers/openai_provider.dart';
import '../ai/providers/grok_provider.dart';
import '../ai/providers/gemini_provider.dart';
import '../ai/providers/deepseek_provider.dart';
import '../state/ai_controller.dart';
import '../state/workspace_controller.dart';
import '../ai/semantic_search_service.dart';
import '../ai/semantic_search_service_impl.dart';

class ServiceLocator {
  static final GetIt _getIt = GetIt.instance;

  static Future<void> init() async {
    final localMessageStore = LocalMessageStore();
    await localMessageStore.init();
    final uiSettingsController = UiSettingsController(localMessageStore);
    await uiSettingsController.init();
    final localProController = LocalProController(localMessageStore);
    await localProController.init();
    final localWorkspaceStore = LocalWorkspaceStore();
    await localWorkspaceStore.init();
    final aiService = AiServiceImpl({
      AiProviderType.openai: OpenAiProvider(),
      AiProviderType.grok: GrokProvider(),
      AiProviderType.gemini: GeminiProvider(),
      AiProviderType.deepseek: DeepSeekProvider(),
    });
    final aiController = AiController(localMessageStore, aiService);
    await aiController.init();
    final workspaceRepository = WorkspaceRepositoryImpl(localWorkspaceStore, localMessageStore);
    final workspaceController = WorkspaceController(workspaceRepository);
    await workspaceController.init();
    _getIt
      ..registerLazySingleton<FlutterSecureStorage>(FlutterSecureStorage.new)
      ..registerSingleton<LocalMessageStore>(localMessageStore)
      ..registerSingleton<LocalWorkspaceStore>(localWorkspaceStore)
      ..registerSingleton<UiSettingsController>(uiSettingsController)
      ..registerSingleton<LocalProController>(localProController)
      ..registerSingleton<AiService>(aiService)
      ..registerSingleton<AiController>(aiController)
      ..registerSingleton<WorkspaceRepository>(workspaceRepository)
      ..registerSingleton<WorkspaceController>(workspaceController)
      ..registerSingleton<SemanticSearchService>(SemanticSearchServiceImpl(aiService))
      ..registerLazySingleton<AuthStorage>(
        () => AuthStorage(_getIt<FlutterSecureStorage>()),
      )
      ..registerLazySingleton<ApiClient>(
        () => ApiClient(_getIt<AuthStorage>()),
      )
      ..registerLazySingleton<TelegramGateway>(
        () => TelegramGatewayImpl(
          _getIt<ApiClient>(),
          _getIt<AuthStorage>(),
        ),
      )
      ..registerLazySingleton<AuthRepository>(
        () => AuthRepositoryImpl(
          _getIt<TelegramGateway>(),
          _getIt<AuthStorage>(),
        ),
      )
      ..registerLazySingleton<AccountRepository>(
        () => AccountRepositoryImpl(_getIt<TelegramGateway>()),
      )
      ..registerLazySingleton<ChatRepository>(
        () => ChatRepositoryImpl(_getIt<TelegramGateway>()),
      )
      ..registerLazySingleton<AiRepository>(
        () => AiRepositoryImpl(_getIt<TelegramGateway>()),
      )
      ..registerLazySingleton<PluginRepository>(
        () => PluginRepositoryImpl(_getIt<TelegramGateway>()),
      )
      ..registerLazySingleton<FolderRepository>(
        () => FolderRepositoryImpl(_getIt<TelegramGateway>()),
      )
      ..registerLazySingleton<SearchRepository>(
        () => SearchRepositoryImpl(_getIt<TelegramGateway>()),
      )
      ..registerLazySingleton<SmartViewRepository>(
        () => SmartViewRepositoryImpl(_getIt<LocalMessageStore>()),
      );
  }

  static T get<T extends Object>() => _getIt<T>();
}
