# translate_ko_jp

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## 모델 설정 (Model setup)

모델 다운로드 소스는 빌드/실행 시 `--dart-define` 플래그로 설정합니다.

The model download source is configured at build/run time via `--dart-define` flags — no secrets are ever hardcoded.

```sh
flutter run \
  --dart-define=MODEL_URL=https://huggingface.co/<org>/<repo>/resolve/main/<file>.task \
  --dart-define=HF_TOKEN=<your_hf_token> \
  --dart-define=MODEL_SHA256=<optional_lowercase_hex_sha256>
```

| Variable | Required | Description |
|----------|----------|-------------|
| `MODEL_URL` | No (has default) | Full HTTPS resolve URL of the `.task` model file. Defaults to a best-guess Hugging Face URL — **verify the exact path before release**. |
| `HF_TOKEN` | For private repos | Hugging Face API token. Injected as `Authorization: Bearer <token>` header. **Never commit this token.** |
| `MODEL_SHA256` | Recommended | Lowercase hex SHA-256 of the downloaded file. If omitted, checksum verification is skipped and a warning is logged. |

For release builds, supply these via CI secrets (e.g. `--dart-define=HF_TOKEN=$HF_TOKEN`).
