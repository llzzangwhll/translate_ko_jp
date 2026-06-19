import 'package:permission_handler/permission_handler.dart';
import 'permission_service.dart';

class PermissionServiceImpl implements PermissionService {
  @override
  Future<MicPermission> ensureMicrophone() async {
    final status = await Permission.microphone.request();
    if (status.isGranted) return MicPermission.granted;
    if (status.isPermanentlyDenied || status.isRestricted) {
      return MicPermission.permanentlyDenied;
    }
    return MicPermission.denied;
  }

  @override
  Future<void> openSettings() => openAppSettings();
}
