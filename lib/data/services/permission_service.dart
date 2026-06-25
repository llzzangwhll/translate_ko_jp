enum PermissionResult { granted, denied, permanentlyDenied }

abstract interface class PermissionService {
  Future<PermissionResult> ensureMicrophone();
  Future<PermissionResult> ensureCamera();
  Future<void> openSettings();
}
