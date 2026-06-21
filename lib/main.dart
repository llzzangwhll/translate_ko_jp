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
  var status = await modelRepo.currentStatus();

  // The native engine keeps the model in memory only, so after a fresh launch
  // the file can exist on disk (`downloaded`) while nothing is loaded. Load it
  // now — the native splash covers this — so translation works without sending
  // the user back through the setup screen. If the load fails, fall through to
  // setup, which re-attempts the load and surfaces the error with a retry.
  if (status == ModelStatus.downloaded) {
    await modelRepo.load();
    status = await modelRepo.currentStatus();
  }

  runApp(TranslateApp(
    initialRoute:
        status == ModelStatus.loaded ? Routes.translation : Routes.setup,
  ));
}
