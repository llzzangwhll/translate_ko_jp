import 'package:permission_handler/permission_handler.dart';
import 'permission_service.dart';

class PermissionServiceImpl implements PermissionService {
  @override
  Future<PermissionResult> ensureMicrophone() => _request(Permission.microphone);

  @override
  Future<PermissionResult> ensureCamera() => _request(Permission.camera);

  Future<PermissionResult> _request(Permission permission) async {
    final status = await permission.request();
    if (status.isGranted) return PermissionResult.granted;
    if (status.isPermanentlyDenied || status.isRestricted) {
      return PermissionResult.permanentlyDenied;
    }
    return PermissionResult.denied;
  }

  @override
  Future<void> openSettings() => openAppSettings();
}
