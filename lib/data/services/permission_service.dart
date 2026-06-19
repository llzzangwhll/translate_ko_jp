enum MicPermission { granted, denied, permanentlyDenied }

abstract interface class PermissionService {
  Future<MicPermission> ensureMicrophone();
  Future<void> openSettings();
}
