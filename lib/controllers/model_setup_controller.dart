import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import '../services/gemma_service.dart';

class ModelSetupController extends GetxController {
  final _gemma = Get.find<GemmaService>();

  final status = ''.obs;
  final isBusy = false.obs;
  final progress = 0.0.obs;

  Future<bool> pickModelFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      dialogTitle: 'Gemma 모델 파일 선택 (.bin 또는 .task)',
    );

    if (result == null || result.files.single.path == null) return false;

    final sourcePath = result.files.single.path!;
    final fileName = result.files.single.name;
    final fileSize = result.files.single.size;

    isBusy.value = true;
    status.value = '모델 파일 복사 중... ($fileName)';
    progress.value = 0;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final destPath = '${appDir.path}/$fileName';
      final sourceFile = File(sourcePath);
      final destFile = File(destPath);

      final input = sourceFile.openRead();
      final output = destFile.openWrite();
      int copied = 0;

      await for (final chunk in input) {
        output.add(chunk);
        copied += chunk.length;
        progress.value = copied / fileSize;
        status.value =
            '복사 중... ${(copied / 1024 / 1024).toStringAsFixed(0)}MB / '
            '${(fileSize / 1024 / 1024).toStringAsFixed(0)}MB';
      }
      await output.flush();
      await output.close();

      status.value = '모델 로딩 중... (잠시 기다려주세요)';
      progress.value = 0;

      final loaded = await _gemma.loadModel(modelPath: destPath);
      if (loaded) return true;

      isBusy.value = false;
      status.value = '모델 로딩 실패. 올바른 모델 파일인지 확인하세요.';
      return false;
    } catch (e) {
      isBusy.value = false;
      status.value = '오류: $e';
      return false;
    }
  }

  Future<bool> tryAutoDetect() async {
    isBusy.value = true;
    status.value = '기기에서 모델 파일 검색 중...';

    try {
      final loaded = await _gemma.loadModel();
      if (loaded) return true;

      isBusy.value = false;
      status.value = '모델을 찾을 수 없습니다. 직접 파일을 선택해주세요.';
      return false;
    } catch (e) {
      isBusy.value = false;
      status.value = e.toString();
      return false;
    }
  }
}
