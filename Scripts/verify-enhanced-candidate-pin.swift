#!/usr/bin/env swift

import Foundation

private let expectedRevision = "19600a485baa4998812e4654b70d2bab8f2c9949"

private struct ResolvedFile: Decodable {
  struct Pin: Decodable {
    struct State: Decodable {
      let revision: String
      let version: String?
    }

    let identity: String
    let state: State
  }

  let pins: [Pin]
}

guard CommandLine.arguments.count == 2 else {
  fputs("usage: verify-enhanced-candidate-pin.swift <Package.resolved>\n", stderr)
  exit(2)
}

do {
  let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
  let resolved = try JSONDecoder().decode(ResolvedFile.self, from: data)
  let fluidAudioPins = resolved.pins.filter { $0.identity == "fluidaudio" }
  guard fluidAudioPins.count == 1,
    fluidAudioPins[0].state.revision == expectedRevision
  else {
    fputs("error: root candidate resolution is not pinned to FluidAudio \(expectedRevision)\n", stderr)
    exit(1)
  }
  print("Root candidate resolution pins FluidAudio \(expectedRevision).")
} catch {
  fputs("error: unable to verify root candidate resolution: \(error)\n", stderr)
  exit(1)
}
