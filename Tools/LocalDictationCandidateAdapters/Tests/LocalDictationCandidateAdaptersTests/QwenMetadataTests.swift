import Testing
@testable import QwenASRSpikeContract

@Test func qwenMetadataBindsTheSherpaArchive() {
  #expect(QwenASRArtifactManifests.sherpa.runtimeArchive.sizeBytes == 17_716_081)
  #expect(QwenASRArtifactManifests.sherpa.modelArchive.sizeBytes == 878_702_423)
}
