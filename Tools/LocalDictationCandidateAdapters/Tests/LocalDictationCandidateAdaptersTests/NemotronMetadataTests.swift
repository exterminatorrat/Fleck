import Testing
@testable import NemotronASRSpikeContract

@Test func nemotronModelIdentityIsPinned() {
  let model = NemotronASRMetadata.candidate.model

  #expect(model.repository == "nvidia/nemotron-3.5-asr-streaming-0.6b")
  #expect(model.revision == "1c8deaecc64b91f034d73e08dd8b64625eb3395d")
  #expect(model.fileName == "nemotron-3.5-asr-streaming-0.6b.q8_0.gguf")
  #expect(model.fileSHA256 == "a5c435f294eea8f88ce68dd27b8c3bfea7f777cb2fbba04fcd30eaa555f429ae")
  #expect(model.fileSizeBytes == 741_548_352)
  #expect(model.license == "OpenMDW-1.1")
}

@Test func nemotronRuntimeRouteAndLicensesArePinned() {
  let runtime = NemotronASRMetadata.candidate.sourceRuntime

  #expect(runtime.repository == "NVIDIA/NeMo-Speech.cpp")
  #expect(runtime.sourceCommit == "5be7bfb104802131e61fe679b3f1401b27270216")
  #expect(runtime.upstreamVersion == "1.0.0")
  #expect(runtime.stableCHeader == "include/nemo_speech/asr.h")
  #expect(runtime.abi == "nemo-speech-asr 1.0.0")
  #expect(runtime.license == "Apache-2.0")
  #expect(runtime.noticeFiles == ["NOTICE", "THIRD_PARTY_NOTICES.md"])
}

@Test func nemotronDependencyPinsAreExact() {
  let pins = Dictionary(
    uniqueKeysWithValues: NemotronASRMetadata.candidate.sourceRuntime.dependencies.map {
      ($0.name, $0.commit)
    }
  )

  #expect(pins == [
    "ggml": "c03b4e2bcece5134827881af90242086daf75be5",
    "llama.cpp": "560445bf34c87356ad0f8d80fb03ec5488850b65",
    "riva-common": "71df98266725320a6b6b3a9f32a6da832dc93691f",
    "cpp-httplib": "62d899feac3cf9215a55f2b43da250fdd98d2156",
    "cppjieba": "b3602bef7d1f67521a61788a74fb5801a0e62cd3",
    "flashlight-text": "49e163ab1e7b8108922512c294ab8513b89f404c",
    "kenlm": "4cb443e60b7bf2c0ddf3c745378f76cb59e254e5",
    "open_jtalk": "1e52154e6677d02dcb4b7f15453e65b5ca1cb6aa",
  ])
}

@Test func nemotronBuildPresetsDescribeCPUAndMetalIntent() {
  let presets = NemotronASRMetadata.candidate.sourceRuntime.buildPresets

  #expect(presets.map(\.name) == [
    "CPU Release / Ninja / C++17",
    "Metal Release / Ninja / C++17",
  ])
  #expect(presets.map(\.accelerator) == ["CPU", "Metal"])
  #expect(presets.allSatisfy {
    $0.configuration == "Release" && $0.generator == "Ninja" && $0.cxxStandard == "C++17"
  })
  #expect(presets[0].cmakeDefinitions == ["GGML_METAL=OFF"])
  #expect(presets[1].cmakeDefinitions == ["GGML_METAL=ON"])
}

@Test func nemotronCompiledRuntimeRemainsStructurallyUnadmitted() {
  let packet = NemotronASRMetadata.candidate
  let runtime = packet.sourceRuntime.compiledRuntime

  #expect(runtime.status == .unadmitted)
  #expect(runtime.isAdmitted == false)
  #expect(runtime.dylibArchiveFileName == nil)
  #expect(runtime.dylibArchiveSHA256 == nil)
  #expect(runtime.dylibArchiveSizeBytes == nil)
  #expect(runtime.unpackedFileIdentities.isEmpty)
  #expect(packet.nativeRuntimeAdmitted == false)
  #expect(packet.modelQualityAdmitted == false)
  #expect(packet.admitted == false)
  #expect(throws: NemotronRuntimeAdmissionError.self) {
    try runtime.requireAdmitted()
  }
}
