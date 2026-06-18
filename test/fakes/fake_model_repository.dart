import 'package:translate_ko_jp/core/result.dart';
import 'package:translate_ko_jp/data/repositories/model_repository.dart';
import 'package:translate_ko_jp/data/services/model_download_service.dart';
import 'package:translate_ko_jp/domain/entities/model_status.dart';

class FakeModelRepository implements ModelRepository {
  ModelStatus statusValue = ModelStatus.notDownloaded;
  List<DownloadProgress> downloadScript = const [];
  Result<void> loadResult = const Ok(null);

  bool loadCalled = false;
  int statusCalls = 0;

  @override
  Future<ModelStatus> currentStatus() async {
    statusCalls++;
    return statusValue;
  }

  @override
  Stream<DownloadProgress> download() async* {
    for (final p in downloadScript) {
      yield p;
    }
  }

  @override
  Future<Result<void>> load() async {
    loadCalled = true;
    return loadResult;
  }
}
