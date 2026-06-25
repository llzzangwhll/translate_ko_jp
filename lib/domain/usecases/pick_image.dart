import '../../data/services/image_picker_service.dart';

/// Returns the path of an image chosen from the camera or album, or null if the
/// user cancelled.
class PickImage {
  final ImagePickerService _picker;
  PickImage(this._picker);

  Future<String?> fromCamera() => _picker.pickFromCamera();
  Future<String?> fromGallery() => _picker.pickFromGallery();
}
