#if os(macOS) && CLEAN_DICTATION_ENHANCED_CANDIDATE
import Foundation
import Testing

@testable import FleckApp

@Suite
struct GemmaCleanupModelManifestTests {
  @Test
  func pinnedManifestDecodesWithExactInventory() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let manifestURL = repositoryRoot.appendingPathComponent(
      "Sources/FleckApp/Resources/GemmaCleanupModelManifest.json"
    )
    let exists = FileManager.default.fileExists(atPath: manifestURL.path)

    #expect(exists)
    guard exists else { return }

    let manifest = try JSONDecoder().decode(
      EnhancedModelManifest.self,
      from: Data(contentsOf: manifestURL)
    )
    let expectedFiles = [
      EnhancedModelFile(
        path: ".gitattributes",
        byteCount: 1_570,
        sha256: "34448b82c17d60fec9b65b1f093c115ddbaadc04beb1b0140b6bfed2e012a930"
      ),
      EnhancedModelFile(
        path: "README.md",
        byteCount: 1_202,
        sha256: "ef1b7148ef260594ac05c36885f6471182f78416ee0d49c76851e7ebe56f4009"
      ),
      EnhancedModelFile(
        path: "added_tokens.json",
        byteCount: 35,
        sha256: "50b2f405ba56a26d4913fd772089992252d7f942123cc0a034d96424221ba946"
      ),
      EnhancedModelFile(
        path: "config.json",
        byteCount: 1_105,
        sha256: "eb080baebedaa32151a71988721a64f0be067fc6cd7e20ca16ba11231f822533"
      ),
      EnhancedModelFile(
        path: "model.safetensors",
        byteCount: 732_577_304,
        sha256: "b6010f6b03a83f973ca8708eb5784d5b0f80c0e7e9143dbb4c95d0eefe39c837"
      ),
      EnhancedModelFile(
        path: "model.safetensors.index.json",
        byteCount: 50_542,
        sha256: "b479eca1f14de16218fc5f45aa270d008944cd3f261f78e90f9b718c8857faef"
      ),
      EnhancedModelFile(
        path: "special_tokens_map.json",
        byteCount: 662,
        sha256: "2f7b0adf4fb469770bb1490e3e35df87b1dc578246c5e7e6fc76ecf33213a397"
      ),
      EnhancedModelFile(
        path: "tokenizer.json",
        byteCount: 33_384_568,
        sha256: "4667f2089529e8e7657cfb6d1c19910ae71ff5f28aa7ab2ff2763330affad795"
      ),
      EnhancedModelFile(
        path: "tokenizer.model",
        byteCount: 4_689_074,
        sha256: "1299c11d7cf632ef3b4e11937501358ada021bbdf7c47638d13c0ee982f2e79c"
      ),
      EnhancedModelFile(
        path: "tokenizer_config.json",
        byteCount: 1_156_959,
        sha256: "be9d72bdf5021aa82d67c3cc60cb0f8ddcc759d4d3f05eb129b9fcc345fc94b7"
      ),
    ]

    #expect(manifest.schemaVersion == 1)
    #expect(manifest.modelID == "mlx-community/gemma-3-1b-it-qat-4bit")
    #expect(manifest.revision == "15fed4eafb456c6fcb2a1165f19ac609670ed14b")
    #expect(manifest.totalByteCount == 771_863_021)
    #expect(manifest.files == expectedFiles)
    #expect(manifest.files.reduce(Int64(0)) { $0 + $1.byteCount } == manifest.totalByteCount)
  }

  @Test
  func noticeIdentifiesPinnedModelTermsAndSeparateWeights() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let noticeURL = repositoryRoot.appendingPathComponent(
      "Sources/FleckApp/Resources/GemmaCleanupNotice.md"
    )
    let notice = try String(contentsOf: noticeURL, encoding: .utf8)

    #expect(notice.contains("mlx-community/gemma-3-1b-it-qat-4bit"))
    #expect(notice.contains("15fed4eafb456c6fcb2a1165f19ac609670ed14b"))
    #expect(notice.contains("https://ai.google.dev/gemma/terms"))
    #expect(notice.contains("locally constitutes acceptance"))
    #expect(notice.contains("Model weights are downloaded separately"))
    #expect(notice.contains("not tracked or redistributed"))
  }
}
#endif
