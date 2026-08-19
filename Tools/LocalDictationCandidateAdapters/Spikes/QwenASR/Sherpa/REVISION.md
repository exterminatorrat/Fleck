# Qwen3-ASR sherpa-onnx admission spike

Status: blocked before payload admission; no production adapter is admitted by
this spike.

## Runtime

- Upstream: [k2-fsa/sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx).
- Runtime release: `v1.13.4`, source commit `142807252687d81b40d6315f23470a1512a00de3`.
- Linked artifact: official [`sherpa-onnx-v1.13.4-macos-shared-onnxruntime-static.xcframework.zip`](https://github.com/k2-fsa/sherpa-onnx/releases/download/xcframework/sherpa-onnx-v1.13.4-macos-shared-onnxruntime-static.xcframework.zip).
- Release archive size: `17,716,081` bytes (official GitHub release API metadata; archive-only provenance).
- Release archive SHA-256 (archive-only provenance): `ef7daa86a1e5f5dcb0ccf53e4e475c3ae24414652c9ae9c3912a82140c86fb1a`.
- Unpacked runtime file identities: unavailable; the route is not admitted.
- Build: Swift 6.3.3, arm64, `-target arm64-apple-macosx13.0`, Release optimization, C API, CPU provider, two runtime threads.
- Expected runtime layout: `SherpaOnnxC.framework/SherpaOnnxC` and `SherpaOnnxC.framework/Headers/sherpa-onnx/c-api/c-api.h`.
- Source checkout used for API audit: commit `634265c9b57642fdd158120148785c89aa281c4b`; the executable is linked against the pinned v1.13.4 official release above.

## Model and conversion provenance

- Owner model: [Qwen/Qwen3-ASR-0.6B](https://huggingface.co/Qwen/Qwen3-ASR-0.6B/tree/5eb144179a02acc5e5ba31e748d22b0cf3e303b0), revision `5eb144179a02acc5e5ba31e748d22b0cf3e303b0`.
- Owner `model.safetensors` SHA-256 at that revision (owner-repository provenance, not the loaded converted payload): `79d6cbd4c98c7bbffe9db2edac07f56cd6637d0d5944b27f6c2b8353840323ea`.
- Owner model license: Apache-2.0.
- Converted artifact: official [`sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25.tar.bz2`](https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25.tar.bz2).
- Converted release archive size: `878,702,423` bytes (official GitHub release API metadata; archive-only provenance).
- Converted release archive SHA-256 (archive-only provenance): `393f8a14e2f5fb96746aaab342997a40641001fbd5bf9592a080a8329178ee96`.
- Unpacked model/runtime per-file identities: unavailable; no converted payload is admitted.
- Expected model layout: `conv_frontend.onnx`, `encoder.int8.onnx`, `decoder.int8.onnx`, `tokenizer/vocab.json`, `tokenizer/merges.txt`, and `tokenizer/tokenizer_config.json`.
- Conversion provenance: the k2-fsa release asset and the Qwen3 C API implementation at the pinned sherpa-onnx source checkout; no community model mirror or unverified conversion was used.

## Runtime semantics and gates

- Qwen3 through this C API is offline/final-only. The spike emits no partial events and does not claim true streaming.
- The shared protocol limit of 100 phrases is enforced, but this Qwen offline model cannot accept per-request context: the upstream per-stream hotword API aborts with `Only transducer models support contextual biasing.` The spike therefore rejects nonempty context with `context-unsupported-by-sherpa-qwen3-offline-api` before crossing that API boundary.
- Locale hints are restricted to `en` and `zh` mappings. Audio is local absolute PCM WAV and is not fetched or resampled by the adapter.
- Load/unload is repeatable in the historical spike. The checked-in manifest has no trusted per-file identities, so startup fails with `artifact-identity-unadmitted` before model layout or recognizer construction. Cancellation is explicitly reported as unsupported because the offline C API has no load/decode cancellation hook; this is a predeclared admission failure, not a synthetic cancellation result.
- Runtime/model paths are absolute local directories supplied at startup. The executable contains no download code and makes no inference-time network requests.
- Archive sizes and digests above are immutable provenance only. No archive, runtime binary, model weight, or unpacked payload is checked in or fetched by this foundation.
- Historical external no-context probes produced English, Mandarin, and concatenated mixed-language finals; the route emitted no partials. Those observations are not current payload-admission or model-quality evidence. Silence produced `system`, so silence quality is not admitted.
- The 50-cycle lifecycle run and cancellation/load/decode probes are external evidence only; shutdown survivor checks and resident-memory samples are recorded outside the checkout.

## Current blockers

The route cannot pass payload admission because unpacked runtime/model file
identities are unavailable. Caller-supplied hashes cannot create admission; a
later change must add a reviewed immutable per-file identity table before native
load is enabled. It also cannot pass the separate capability gates because
active cancellation and per-request context are unsupported. It remains a
final-only development candidate with no production adapter.
