import Testing
@testable import WhisperASRSpikeContract

@Test func whisperSmallMetadataPinsTheModelArtifact() {
  let model = WhisperASRMetadata.candidate.model

  #expect(model.repository == "ggerganov/whisper.cpp")
  #expect(model.revision == "80da2d8bfee42b0e836fc3a9890373e5defc00a6")
  #expect(model.fileName == "ggml-small.bin")
  #expect(model.fileSHA256 == "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b")
  #expect(model.fileSizeBytes == 487_601_967)
  #expect(model.license == "MIT")
}

@Test func whisperRuntimeMetadataPinsTheSourceAndBuildIntent() {
  let runtime = WhisperASRMetadata.candidate.sourceRuntime

  #expect(runtime.repository == "ggml-org/whisper.cpp")
  #expect(runtime.release == "v1.9.2")
  #expect(runtime.sourceCommit == "306c88f4d1286aec1bf96e544632897886af5501")
  #expect(runtime.license == "MIT")
  #expect(runtime.buildIntent.cmakeDefinitions == [
    "BUILD_SHARED_LIBS=OFF",
    "GGML_METAL=ON",
    "GGML_METAL_EMBED_LIBRARY=ON",
    "WHISPER_CURL=OFF",
    "WHISPER_BUILD_SERVER=OFF",
    "WHISPER_COREML=OFF",
    "WHISPER_OPENVINO=OFF",
    "WHISPER_SDL2=OFF",
    "GGML_OPENMP=OFF",
    "GGML_BLAS=OFF",
    "CMAKE_OSX_DEPLOYMENT_TARGET=14.0",
  ])
}

@Test func whisperCompiledRuntimeRemainsStructurallyUnadmitted() {
  let packet = WhisperASRMetadata.candidate
  let runtime = packet.sourceRuntime.compiledRuntime

  #expect(runtime.status == .unadmitted)
  #expect(runtime.isAdmitted == false)
  #expect(packet.nativeRuntimeAdmitted == false)
  #expect(packet.modelQualityAdmitted == false)
  #expect(packet.admitted == false)
  #expect(throws: WhisperRuntimeAdmissionError.self) {
    try runtime.requireAdmitted()
  }
}
