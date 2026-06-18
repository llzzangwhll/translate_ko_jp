sealed class Failure {
  final String message;
  const Failure(this.message);
}

class PermissionFailure extends Failure { const PermissionFailure(super.message); }
class NetworkFailure extends Failure { const NetworkFailure(super.message); }
class ModelFailure extends Failure { const ModelFailure(super.message); }
class InferenceFailure extends Failure { const InferenceFailure(super.message); }
class StorageFailure extends Failure { const StorageFailure(super.message); }
