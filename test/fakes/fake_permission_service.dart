import 'package:translate_ko_jp/data/services/permission_service.dart';

class FakePermissionService implements PermissionService {
  PermissionResult result;
  PermissionResult cameraResult;
  int openSettingsCalls = 0;

  FakePermissionService({
    this.result = PermissionResult.granted,
    this.cameraResult = PermissionResult.granted,
  });

  @override
  Future<PermissionResult> ensureMicrophone() async => result;

  @override
  Future<PermissionResult> ensureCamera() async => cameraResult;

  @override
  Future<void> openSettings() async => openSettingsCalls++;
}
