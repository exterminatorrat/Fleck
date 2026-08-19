# Nemotron 3.5 ASR Streaming 0.6B Q8 metadata packet

Status: pre-download metadata only. The candidate is not an admitted native
runtime, model-quality result, adapter, or production integration.

## Model identity

- Official model: [nvidia/nemotron-3.5-asr-streaming-0.6b](https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b).
- Revision: `1c8deaecc64b91f034d73e08dd8b64625eb3395d`.
- File: `nemotron-3.5-asr-streaming-0.6b.q8_0.gguf`.
- File SHA-256: `a5c435f294eea8f88ce68dd27b8c3bfea7f777cb2fbba04fcd30eaa555f429ae`.
- File size: `741,548,352` bytes.
- Model license: `OpenMDW-1.1`.

The model file identity is pinned provenance only. It does not admit a native
runtime or model quality.

## Intended NeMo-Speech.cpp source/runtime route

- Upstream: [NVIDIA/NeMo-Speech.cpp](https://github.com/NVIDIA/NeMo-Speech.cpp).
- Source commit: `5be7bfb104802131e61fe679b3f1401b27270216`.
- Upstream version: `1.0.0`.
- Stable C header: `include/nemo_speech/asr.h`.
- ABI: `nemo-speech-asr 1.0.0`.
- License: `Apache-2.0`, with `NOTICE` and `THIRD_PARTY_NOTICES.md` retained as
  required notices.

### Dependency pins

| Dependency | Commit |
| --- | --- |
| `ggml` | `c03b4e2bcece5134827881af90242086daf75be5` |
| `llama.cpp` | `560445bf34c87356ad0f8d80fb03ec5488850b65` |
| `riva-common` | `71df98266725320a6b6b3a9f32a6da832dc93691f` |
| `cpp-httplib` | `62d899feac3cf9215a55f2b43da250fdd98d2153` |
| `cppjieba` | `b3602bef7d1f67521a61788a74fb5801a0e62cd3` |
| `flashlight-text` | `49e163ab1e7b8108922512c294ab8513b89f404c` |
| `kenlm` | `4cb443e60b7bf2c0ddf3c745378f76cb59e254e5` |
| `open_jtalk` | `1e52154e6677d02dcb4b7f15453e65b5ca1cb6aa` |

### Intended build presets

The future route describes CPU and Metal `Release` / `Ninja` / `C++17`
presets. The Metal preset requires `GGML_METAL=ON`; the CPU preset keeps
`GGML_METAL=OFF`. These are build intent only and have not been executed here.

## Compiled-runtime admission boundary

No compiled CPU or Metal dylib archive, archive checksum, archive size, or
unpacked per-file runtime identity is trusted yet. The checked-in contract
therefore exposes only an immutable `unadmitted` runtime status with no caller-
supplied path, hash, size, or file table that can be used to represent
admission. The runtime cannot be admitted until a later reviewed packet binds
those native identities.

No payload was downloaded or built. This packet contains no binary, weight,
archive, downloader, helper, adapter, inference, benchmark, install step, or
UI/app integration.
