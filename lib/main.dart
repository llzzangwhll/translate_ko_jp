import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'app/app.dart';
import 'app/bindings.dart';
import 'app/routes.dart';
import 'data/repositories/model_repository.dart';
import 'domain/entities/model_status.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await registerAllDeps();

  final modelRepo = Get.find<ModelRepository>();
  final status = await modelRepo.currentStatus();
  final ready = status == ModelStatus.loaded || status == ModelStatus.downloaded;

  runApp(TranslateApp(
    initialRoute: ready ? Routes.translation : Routes.setup,
  ));
}
