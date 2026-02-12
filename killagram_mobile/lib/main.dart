import 'package:flutter/material.dart';
import 'core/di/service_locator.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ServiceLocator.init();
  runApp(const KillagramApp());
}
