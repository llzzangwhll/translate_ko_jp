import 'package:translate_ko_jp/data/services/permission_service.dart';

class FakePermissionService implements PermissionService {
  MicPermission result;
  int openSettingsCalls = 0;

  FakePermissionService({this.result = MicPermission.granted});

  @override
  Future<MicPermission> ensureMicrophone() async => result;

  @override
  Future<void> openSettings() async => openSettingsCalls++;
}
