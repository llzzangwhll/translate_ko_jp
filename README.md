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

모델 다운로드 소스(URL · Hugging Face 토큰 · 체크섬)는 **빌드/실행 시 주입**합니다.
소스 코드나 git 히스토리에는 토큰이 들어가지 않습니다.

### 권장: 로컬 `secrets.json` (개인용, 한 번 설정하면 편함)

토큰을 프로젝트 안에 두되 **git에서는 제외**합니다 (`secrets.json`은 `.gitignore`에 등록됨).

1. 템플릿을 복사합니다:

   ```sh
   cp secrets.example.json secrets.json
   ```

2. `secrets.json`에 실제 값을 채웁니다:

   ```json
   {
     "MODEL_URL": "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm",
     "HF_TOKEN": "hf_xxx",
     "MODEL_SHA256": ""
   }
   ```

   > 모델은 Gemma 4 E2B의 **`.litertlm`** (LiteRT-LM) 빌드입니다. 저장소는 **gated**이므로
   > `HF_TOKEN` 계정으로 모델 페이지에서 Gemma 라이선스에 먼저 동의해야 다운로드됩니다.
   > 네이티브 핸들러(Android/iOS)는 `.litertlm`/`.task`/`.bin`을 탐색·로드하지만,
   > 설치된 MediaPipe(`tasks-genai 0.10.22`)가 `.litertlm`을 실제로 로드하는지는
   > 기기에서 확인이 필요합니다 (`docs/ios-verification-checklist.md` 참고).

3. 실행/빌드 시 파일을 주입합니다:

   ```sh
   flutter run   --dart-define-from-file=secrets.json
   flutter build apk --dart-define-from-file=secrets.json
   ```

   > IDE(VS Code / Android Studio)에서는 실행 구성(run configuration)의
   > "Additional run args"에 `--dart-define-from-file=secrets.json`를 한 번만 넣어두면
   > 매번 자동 적용됩니다.

⚠️ `secrets.json`은 절대 커밋하지 마세요. 이 저장소는 GitHub 리모트가 있어, 토큰이 커밋되면
히스토리에 영구 기록되고 Hugging Face가 토큰을 자동 폐기할 수 있습니다. (`secrets.example.json`만 커밋됩니다.)

### 대안: 개별 `--dart-define`

```sh
flutter run \
  --dart-define=MODEL_URL=https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm \
  --dart-define=HF_TOKEN=<your_hf_token> \
  --dart-define=MODEL_SHA256=<optional_lowercase_hex_sha256>
```

| Variable | Required | Description |
|----------|----------|-------------|
| `MODEL_URL` | No (has default) | Full HTTPS resolve URL of the on-device model file. Defaults to the gated Gemma 4 E2B `.litertlm` build on Hugging Face — **accept the license and verify the exact path before release**. |
| `HF_TOKEN` | For private/gated repos | Hugging Face API token. Injected as `Authorization: Bearer <token>` header. Supply via `secrets.json` or `--dart-define`; **never commit it**. |
| `MODEL_SHA256` | Recommended | Lowercase hex SHA-256 of the downloaded file. If omitted, checksum verification is skipped and a warning is logged. |

`flutter test` / `flutter analyze`는 이 값들 없이도 동작합니다(기본값 사용, 다운로드는 하지 않음).
