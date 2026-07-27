#!/usr/bin/env swift

import CryptoKit
import Darwin
import Foundation

private let expectedModelID = "FluidInference/parakeet-tdt-0.6b-v2-coreml"
private let expectedRevision = "ee09c569f73759e6d44c9bd16766f477b2b36d39"
private let expectedTotalByteCount: Int64 = 464_413_247

private struct Manifest: Decodable {
    let schemaVersion: Int
    let modelID: String
    let revision: String
    let totalByteCount: Int64
    let files: [ManifestFile]
}

private struct ManifestFile: Decodable {
    let path: String
    let byteCount: Int64
    let sha256: String
}

private struct VerificationError: Error, CustomStringConvertible {
    let description: String
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw VerificationError(description: message)
    }
}

private func sha256(of url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }

    var hasher = SHA256()
    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
        hasher.update(data: data)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

private func verifyManifest(at manifestURL: URL, installedDirectory: URL?) throws {
    let manifest = try JSONDecoder().decode(
        Manifest.self,
        from: Data(contentsOf: manifestURL)
    )

    try require(manifest.schemaVersion == 1, "unsupported schema version")
    try require(manifest.modelID == expectedModelID, "unexpected model ID")
    try require(manifest.revision == expectedRevision, "unexpected model revision")
    try require(
        manifest.totalByteCount == expectedTotalByteCount,
        "unexpected manifest total byte count"
    )
    try require(manifest.files.count == 21, "unexpected manifest file count")

    var paths = Set<String>()
    var computedTotal: Int64 = 0
    for file in manifest.files {
        let components = file.path.split(separator: "/", omittingEmptySubsequences: false)
        try require(!file.path.isEmpty, "empty file path")
        try require(!file.path.hasPrefix("/"), "absolute file path: \(file.path)")
        try require(!components.contains(".."), "parent path component: \(file.path)")
        try require(paths.insert(file.path).inserted, "duplicate file path: \(file.path)")
        try require(file.byteCount >= 0, "negative byte count: \(file.path)")
        try require(
            file.sha256.count == 64 && file.sha256.allSatisfy(\.isHexDigit),
            "invalid SHA-256: \(file.path)"
        )

        let (total, overflow) = computedTotal.addingReportingOverflow(file.byteCount)
        try require(!overflow, "manifest byte count overflow")
        computedTotal = total

        guard let installedDirectory else {
            continue
        }

        let fileURL = installedDirectory.appendingPathComponent(file.path)
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        try require(
            attributes[.type] as? FileAttributeType == .typeRegular,
            "not a regular file: \(file.path)"
        )
        let installedByteCount = (attributes[.size] as? NSNumber)?.int64Value
        try require(installedByteCount == file.byteCount, "size mismatch: \(file.path)")
        let installedSHA256 = try sha256(of: fileURL)
        try require(
            installedSHA256 == file.sha256.lowercased(),
            "SHA-256 mismatch: \(file.path)"
        )
    }

    try require(computedTotal == expectedTotalByteCount, "file byte counts do not match total")
}

do {
    let arguments = CommandLine.arguments
    try require(
        arguments.count == 2 || arguments.count == 3,
        "usage: \(arguments[0]) <manifest.json> [installed-model-directory]"
    )
    let manifestURL = URL(fileURLWithPath: arguments[1])
    let installedDirectory = arguments.count == 3
        ? URL(fileURLWithPath: arguments[2], isDirectory: true)
        : nil
    try verifyManifest(at: manifestURL, installedDirectory: installedDirectory)
    print("Enhanced model manifest verified.")
} catch {
    FileHandle.standardError.write(Data("Manifest verification failed: \(error)\n".utf8))
    exit(EXIT_FAILURE)
}
