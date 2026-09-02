# Whisper small control pre-download metadata

Status: pre-download metadata only. This packet pins source and model
provenance for a mature control candidate; it does not admit a compiled
runtime, model quality, an adapter, or product integration.

## Model provenance

- Repository: [ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp).
- Revision: `80da2d8bfee42b0e836fc3a9890373e5defc00a6`.
- File: `ggml-small.bin`.
- SHA-256: `1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b`.
- Size: `487,601,967` bytes.
- License: MIT.

The model revision and file digest are immutable provenance for the intended
future payload. No model payload is checked in or downloaded by this packet.

## Runtime source provenance

- Repository: [ggml-org/whisper.cpp](https://github.com/ggml-org/whisper.cpp).
- Release: `v1.9.2`.
- Source commit: `306c88f4d1286aec1bf96e544632897886af5501`.
- License: MIT.

The source commit identifies upstream source provenance only. It is not the
identity of a compiled helper or runtime product.

## Intended future build flags

These flags describe a reproducible future build intent only; no build was
run here:

```text
BUILD_SHARED_LIBS=OFF
GGML_METAL=ON
GGML_METAL_EMBED_LIBRARY=ON
WHISPER_CURL=OFF
WHISPER_BUILD_SERVER=OFF
WHISPER_COREML=OFF
WHISPER_OPENVINO=OFF
WHISPER_SDL2=OFF
GGML_OPENMP=OFF
GGML_BLAS=OFF
CMAKE_OSX_DEPLOYMENT_TARGET=14.0
```

## Compiled helper/runtime identity

The following identities are unknown and intentionally absent from the
executable contract:

- compiled helper/runtime source checkout path or observed checkout identity;
- build invocation, toolchain, and produced product identity;
- compiled product checksum and size; and
- unpacked per-file runtime identities.

The Swift contract exposes only an immutable `unadmitted` compiled-runtime
status. It has no caller constructor or caller-supplied path, checksum, size,
or file table that could represent admission. Native runtime admission,
model-quality admission, and overall candidate admission are all false.

## Evidence boundary

No payload was downloaded or built. This packet contains no native helper,
downloader, adapter, audio/inference path, benchmark, installation, or UI/app
integration. It contains no inference or benchmark evidence and makes no
readiness claim.
