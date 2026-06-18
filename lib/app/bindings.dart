import 'package:get/get.dart';

/// Each flow contributes its own registration function and the integration
/// step (plan 05) wires them together here.
class AppBinding extends Bindings {
  @override
  void dependencies() {
    // Flow registrations are added during integration (plan 05):
    // registerTranslationDeps();
    // registerModelDeps();
    // registerHistoryDeps();
  }
}
