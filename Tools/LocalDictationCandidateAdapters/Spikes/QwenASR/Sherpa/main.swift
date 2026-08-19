import Darwin
import Foundation
import LocalDictationCandidateProtocol

private struct SherpaModelFiles {
  let convFrontend: URL
  let encoder: URL
  let decoder: URL
  let tokenizer: URL

  static func load(from root: URL) throws -> SherpaModelFiles {
    func file(_ relativePath: String) throws -> URL {
      try StartupPathPolicy.requireNonEmptyContainedFile(
        root.appendingPathComponent(relativePath).path,
        within: root,
        field: "model-file-\(relativePath)"
      )
    }

    let tokenizer = root.appendingPathComponent("tokenizer", isDirectory: true)
    _ = try StartupPathPolicy.requireLocalDirectory(tokenizer.path, field: "tokenizer")
    _ = try StartupPathPolicy.requireNonEmptyContainedFile(
      tokenizer.appendingPathComponent("vocab.json").path,
      within: root,
      field: "model-file-tokenizer-vocab.json"
    )
    _ = try StartupPathPolicy.requireNonEmptyContainedFile(
      tokenizer.appendingPathComponent("merges.txt").path,
      within: root,
      field: "model-file-tokenizer-merges.txt"
    )
    _ = try StartupPathPolicy.requireNonEmptyContainedFile(
      tokenizer.appendingPathComponent("tokenizer_config.json").path,
      within: root,
      field: "model-file-tokenizer-config.json"
    )
    return SherpaModelFiles(
      convFrontend: try file("conv_frontend.onnx"),
      encoder: try file("encoder.int8.onnx"),
      decoder: try file("decoder.int8.onnx"),
      tokenizer: tokenizer.resolvingSymlinksInPath().standardizedFileURL
    )
  }
}

private struct SherpaConfiguration {
  let runtimeRoot: URL
  let modelRoot: URL
  let model: SherpaModelFiles

  init(arguments: [String]) throws {
    var values: [String: String] = [:]
    var index = 1
    while index < arguments.count {
      guard index + 1 < arguments.count else { throw StartupPathError.missing("argument") }
      let key = arguments[index]
      guard key == "--runtime-root" || key == "--model-root", values[key] == nil else {
        throw StartupPathError.invalidArgument
      }
      values[key] = arguments[index + 1]
      index += 2
    }
    guard let runtimePath = values["--runtime-root"], let modelPath = values["--model-root"] else {
      throw StartupPathError.missing("runtime-or-model-root")
    }
    runtimeRoot = try StartupPathPolicy.requireLocalDirectory(runtimePath, field: "runtime-root")
    modelRoot = try StartupPathPolicy.requireLocalDirectory(modelPath, field: "model-root")
    model = try SherpaModelFiles.load(from: modelRoot)
  }
}

private enum SherpaSpikeError: Error, CustomStringConvertible {
  case runtimeFailure(String)
  case notLoaded
  case invalidLocale(String)
  case contextUnsupported
  case cancellationUnsupported

  var description: String {
    switch self {
    case .runtimeFailure(let message): return message
    case .notLoaded: return "model-not-loaded"
    case .invalidLocale(let locale): return "unsupported-locale-\(locale)"
    case .contextUnsupported: return "context-unsupported-by-sherpa-qwen3-offline-api"
    case .cancellationUnsupported: return "cancellation-unsupported-by-offline-runtime"
    }
  }
}

private final class SherpaRecognizer {
  private let model: SherpaModelFiles
  private var recognizer: OpaquePointer?

  init(model: SherpaModelFiles) {
    self.model = model
  }

  deinit {
    unload()
  }

  func load() throws {
    unload()
    let created: OpaquePointer? = model.convFrontend.path.withCString { convFrontend in
      model.encoder.path.withCString { encoder in
        model.decoder.path.withCString { decoder in
          model.tokenizer.path.withCString { tokenizer in
            "greedy_search".withCString { decodingMethod in
              "cpu".withCString { provider in
                var config = SherpaOnnxOfflineRecognizerConfig()
                config.feat_config.sample_rate = 16_000
                config.feat_config.feature_dim = 80
                config.model_config.num_threads = 2
                config.model_config.debug = 0
                config.model_config.provider = provider
                config.model_config.qwen3_asr.conv_frontend = convFrontend
                config.model_config.qwen3_asr.encoder = encoder
                config.model_config.qwen3_asr.decoder = decoder
                config.model_config.qwen3_asr.tokenizer = tokenizer
                config.model_config.qwen3_asr.max_total_len = 512
                config.model_config.qwen3_asr.max_new_tokens = 128
                config.model_config.qwen3_asr.temperature = 1e-6
                config.model_config.qwen3_asr.top_p = 0.8
                config.model_config.qwen3_asr.seed = 42
                config.model_config.qwen3_asr.hotwords = nil
                config.decoding_method = decodingMethod
                return SherpaOnnxCreateOfflineRecognizer(&config)
              }
            }
          }
        }
      }
    }
    guard let created else {
      throw SherpaSpikeError.runtimeFailure("sherpa-recognizer-create-failed")
    }
    recognizer = created
  }

  func unload() {
    if let recognizer {
      SherpaOnnxDestroyOfflineRecognizer(recognizer)
      self.recognizer = nil
    }
  }

  func transcribe(
    audio: PCM16Wave,
    localeIdentifier: String,
    contextPhrases: [String]
  ) throws -> String {
    guard let recognizer else { throw SherpaSpikeError.notLoaded }
    let language = try Self.languageCode(for: localeIdentifier)
    let hotwords = try BoundedContext.hotwordArgument(contextPhrases)
    guard hotwords.isEmpty else { throw SherpaSpikeError.contextUnsupported }
    let stream: OpaquePointer? = SherpaOnnxCreateOfflineStream(recognizer)
    guard let stream else {
      throw SherpaSpikeError.runtimeFailure("sherpa-stream-create-failed")
    }
    defer { SherpaOnnxDestroyOfflineStream(stream) }

    language.withCString { SherpaOnnxOfflineStreamSetOption(stream, "language", $0) }
    audio.samples.withUnsafeBufferPointer { samples in
      SherpaOnnxAcceptWaveformOffline(stream, Int32(audio.sampleRate), samples.baseAddress, Int32(samples.count))
    }
    SherpaOnnxDecodeOfflineStream(recognizer, stream)
    guard let result = SherpaOnnxGetOfflineStreamResult(stream) else {
      throw SherpaSpikeError.runtimeFailure("sherpa-result-failed")
    }
    defer { SherpaOnnxDestroyOfflineRecognizerResult(result) }
    guard let text = result.pointee.text else { return "" }
    return String(cString: text)
  }

  private static func languageCode(for localeIdentifier: String) throws -> String {
    let normalized = localeIdentifier.lowercased()
    if normalized.hasPrefix("en") { return "en" }
    if normalized.hasPrefix("zh") { return "zh" }
    throw SherpaSpikeError.invalidLocale(localeIdentifier)
  }
}

private enum SherpaQwenASRSpike {
  static let runtimeVersion = "sherpa-onnx@v1.13.4;commit=142807252687d81b40d6315f23470a1512a00de3;offline-qwen3;cpu;threads=2"
  static let modelRevision = "sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25;payload-identity=unverified;license=Apache-2.0"

  static func run(arguments: [String]) throws {
    try QwenASRArtifactManifests.sherpa.requireAdmitted()
    let configuration = try SherpaConfiguration(arguments: arguments)
    _ = configuration.runtimeRoot
    let input = JSONLinesInput()
    let output = JSONLinesOutput()
    let recognizer = SherpaRecognizer(model: configuration.model)
    var loaded = false

    while let line = try input.nextLine() {
      let request: CandidateAdapterRequest
      do {
        request = try JSONLinesCodec.decodeRequest(line)
      } catch {
        try output.write(.failure(requestID: "protocol", code: "invalid-request", message: "request-decode-failed"))
        continue
      }

      do {
        switch request.operation {
        case .load:
          let milliseconds = try SpikeClock.milliseconds {
            try recognizer.load()
          }
          loaded = true
          try output.write(.measurement(requestID: request.requestID, name: "loadMilliseconds", value: milliseconds, unit: "ms"))
          try output.write(.ready(
            requestID: request.requestID,
            runtimeVersion: runtimeVersion,
            modelRevision: modelRevision
          ))
        case .transcribe:
          guard loaded, let audioPath = request.audioPath, let sampleRate = request.sampleRate,
            let localeIdentifier = request.localeIdentifier else {
            throw SherpaSpikeError.notLoaded
          }
          let wave = try WaveReader.read(URL(fileURLWithPath: audioPath), expectedSampleRate: sampleRate)
          var transcript = ""
          let milliseconds = try SpikeClock.milliseconds {
            transcript = try recognizer.transcribe(
              audio: wave,
              localeIdentifier: localeIdentifier,
              contextPhrases: request.contextPhrases
            )
          }
          try output.write(.measurement(requestID: request.requestID, name: "decodeMilliseconds", value: milliseconds, unit: "ms"))
          try output.write(.final(requestID: request.requestID, transcript: transcript))
        case .clean:
          try output.write(.final(requestID: request.requestID, transcript: request.transcript ?? ""))
        case .cancel:
          throw SherpaSpikeError.cancellationUnsupported
        case .unload:
          recognizer.unload()
          loaded = false
          try output.write(.unloaded(requestID: request.requestID))
        case .shutdown:
          recognizer.unload()
          loaded = false
          try output.write(.unloaded(requestID: request.requestID))
          return
        }
      } catch {
        try output.write(.failure(requestID: request.requestID, code: "spike-failure", message: String(describing: error)))
      }
    }
  }
}

@main
struct Main {
  static func main() {
    do {
      try SherpaQwenASRSpike.run(arguments: CommandLine.arguments)
    } catch {
      FileHandle.standardError.write(Data("startup-failure:\(error)\n".utf8))
      Darwin.exit(2)
    }
  }
}
