/// Picks an image from the camera or the photo album. Returns the local file
/// path of the chosen image, or null if the user cancelled.
abstract interface class ImagePickerService {
  Future<String?> pickFromCamera();
  Future<String?> pickFromGallery();
}
