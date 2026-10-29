import AppKit
import Darwin
import Foundation
import Testing

private enum ExitCaptureFailure: Error {
  case unavailable
  case alreadyExists
}

private struct ExitCaptureFileIdentity: Equatable {
  let device: UInt64
  let inode: UInt64
}

private struct ExitCaptureFile {
  let data: Data
  let identity: ExitCaptureFileIdentity
}

private enum ExitCaptureFiles {
  static let recordLimit = 512
  static let evidenceRecordLimit = 6
  static let evidenceByteLimit = 4_096

  static func read(
    at path: String,
    limit: Int,
    allowMissing: Bool = false
  ) throws -> ExitCaptureFile? {
    try validatePrivateDirectory(for: path)
    let descriptor = path.withCString {
      Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
    }
    guard descriptor >= 0 else {
      if allowMissing, errno == ENOENT { return nil }
      throw ExitCaptureFailure.unavailable
    }
    defer { _ = Darwin.close(descriptor) }

    var before = stat()
    var beforePath = stat()
    guard fstat(descriptor, &before) == 0,
      path.withCString({ Darwin.lstat($0, &beforePath) }) == 0,
      isPrivateRegularFile(before), sameFile(before, beforePath),
      before.st_size >= 0, before.st_size <= off_t(limit)
    else {
      throw ExitCaptureFailure.unavailable
    }

    var contents = Data()
    var buffer = [UInt8](repeating: 0, count: Swift.min(1_024, limit + 1))
    while true {
      let capacity = Swift.min(buffer.count, limit - contents.count + 1)
      let count = buffer.withUnsafeMutableBytes { raw -> Int in
        guard let base = raw.baseAddress else { return -1 }
        return Darwin.read(descriptor, base, capacity)
      }
      if count == 0 { break }
      if count < 0 {
        if errno == EINTR { continue }
        throw ExitCaptureFailure.unavailable
      }
      guard contents.count + count <= limit else {
        throw ExitCaptureFailure.unavailable
      }
      contents.append(contentsOf: buffer.prefix(count))
    }

    var after = stat()
    var afterPath = stat()
    guard fstat(descriptor, &after) == 0,
      path.withCString({ Darwin.lstat($0, &afterPath) }) == 0,
      isPrivateRegularFile(after), sameFile(before, after), sameFile(after, afterPath),
      after.st_size == off_t(contents.count)
    else {
      throw ExitCaptureFailure.unavailable
    }
    return ExitCaptureFile(
      data: contents,
      identity: ExitCaptureFileIdentity(
        device: UInt64(truncatingIfNeeded: after.st_dev),
        inode: UInt64(truncatingIfNeeded: after.st_ino)
      )
    )
  }

  static func writeOnce(at path: String, contents: Data, limit: Int) throws {
    guard contents.count <= limit, contents.last == 10 else {
      throw ExitCaptureFailure.unavailable
    }
    try validatePrivateDirectory(for: path)
    let url = URL(fileURLWithPath: path)
    let directoryPath = url.deletingLastPathComponent().path
    let name = url.lastPathComponent
    let pendingName = name + ".pending"
    let directory = directoryPath.withCString {
      Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    }
    guard directory >= 0 else { throw ExitCaptureFailure.unavailable }
    defer { _ = Darwin.close(directory) }
    var directoryStatus = stat()
    var directoryPathStatus = stat()
    guard fstat(directory, &directoryStatus) == 0,
      directoryPath.withCString({ Darwin.lstat($0, &directoryPathStatus) }) == 0,
      sameFile(directoryStatus, directoryPathStatus),
      directoryStatus.st_uid == geteuid(),
      directoryStatus.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
      directoryStatus.st_mode & mode_t(0o777) == mode_t(0o700)
    else { throw ExitCaptureFailure.unavailable }
    var finalStatus = stat()
    if name.withCString({ fstatat(directory, $0, &finalStatus, AT_SYMLINK_NOFOLLOW) }) == 0 {
      throw ExitCaptureFailure.alreadyExists
    }
    guard errno == ENOENT else { throw ExitCaptureFailure.unavailable }
    let descriptor = pendingName.withCString {
      Darwin.openat(
        directory, $0,
        O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC,
        mode_t(0o600)
      )
    }
    guard descriptor >= 0 else {
      throw ExitCaptureFailure.unavailable
    }
    defer { _ = Darwin.close(descriptor) }

    var before = stat()
    var beforePath = stat()
    guard fstat(descriptor, &before) == 0,
      pendingName.withCString({ fstatat(directory, $0, &beforePath, AT_SYMLINK_NOFOLLOW) }) == 0,
      isPrivateRegularFile(before), before.st_mode & mode_t(0o777) == mode_t(0o600),
      sameFile(before, beforePath), before.st_size == 0
    else {
      throw ExitCaptureFailure.unavailable
    }
    if name.withCString({ fstatat(directory, $0, &finalStatus, AT_SYMLINK_NOFOLLOW) }) == 0 {
      throw ExitCaptureFailure.alreadyExists
    }
    guard errno == ENOENT else { throw ExitCaptureFailure.unavailable }

    var offset = 0
    while offset < contents.count {
      let count = contents.withUnsafeBytes { raw -> Int in
        guard let base = raw.baseAddress else { return -1 }
        return Darwin.write(descriptor, base.advanced(by: offset), raw.count - offset)
      }
      if count < 0 {
        if errno == EINTR { continue }
        throw ExitCaptureFailure.unavailable
      }
      guard count > 0 else { throw ExitCaptureFailure.unavailable }
      offset += count
    }
    guard fsync(descriptor) == 0 else { throw ExitCaptureFailure.unavailable }

    var after = stat()
    var afterPath = stat()
    guard fstat(descriptor, &after) == 0,
      pendingName.withCString({ fstatat(directory, $0, &afterPath, AT_SYMLINK_NOFOLLOW) }) == 0,
      isPrivateRegularFile(after), sameFile(before, after), sameFile(after, afterPath),
      after.st_mode & mode_t(0o777) == mode_t(0o600),
      after.st_size == off_t(contents.count)
    else {
      throw ExitCaptureFailure.unavailable
    }
    let published = pendingName.withCString { source in
      name.withCString { destination in
        renameatx_np(directory, source, directory, destination, UInt32(RENAME_EXCL))
      }
    }
    guard published == 0 else { throw ExitCaptureFailure.unavailable }
    var publishedStatus = stat()
    var publishedPathStatus = stat()
    var currentDirectoryStatus = stat()
    guard fstat(descriptor, &publishedStatus) == 0,
      name.withCString({ fstatat(directory, $0, &publishedPathStatus, AT_SYMLINK_NOFOLLOW) }) == 0,
      directoryPath.withCString({ Darwin.lstat($0, &currentDirectoryStatus) }) == 0,
      sameFile(directoryStatus, currentDirectoryStatus),
      currentDirectoryStatus.st_uid == geteuid(),
      currentDirectoryStatus.st_mode & mode_t(0o777) == mode_t(0o700),
      isPrivateRegularFile(publishedStatus),
      publishedStatus.st_mode & mode_t(0o777) == mode_t(0o600),
      sameFile(before, publishedStatus), sameFile(publishedStatus, publishedPathStatus),
      publishedStatus.st_size == off_t(contents.count)
    else { throw ExitCaptureFailure.unavailable }
  }

  static func writeIdempotently(
    at path: String,
    contents: Data,
    existingRecordIsValid: (Data) -> Bool
  ) throws {
    do {
      try writeOnce(at: path, contents: contents, limit: recordLimit)
    } catch ExitCaptureFailure.alreadyExists {
      guard let existing = try read(at: path, limit: recordLimit),
        existingRecordIsValid(existing.data)
      else {
        throw ExitCaptureFailure.unavailable
      }
    }
  }

  private static func validatePrivateDirectory(for path: String) throws {
    guard path.hasPrefix("/"), !path.utf8.contains(0) else {
      throw ExitCaptureFailure.unavailable
    }
    let directoryPath = URL(fileURLWithPath: path).deletingLastPathComponent().path
    let descriptor = directoryPath.withCString {
      Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    }
    guard descriptor >= 0 else { throw ExitCaptureFailure.unavailable }
    defer { _ = Darwin.close(descriptor) }

    var opened = stat()
    var current = stat()
    guard fstat(descriptor, &opened) == 0,
      directoryPath.withCString({ Darwin.lstat($0, &current) }) == 0,
      sameFile(opened, current), opened.st_uid == geteuid(),
      opened.st_mode & mode_t(0o777) == mode_t(0o700),
      opened.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
    else {
      throw ExitCaptureFailure.unavailable
    }
  }

  private static func isPrivateRegularFile(_ status: stat) -> Bool {
    status.st_uid == geteuid() && status.st_nlink == 1
      && status.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
  }

  private static func sameFile(_ first: stat, _ second: stat) -> Bool {
    first.st_dev == second.st_dev && first.st_ino == second.st_ino
  }
}

private struct ExitCaptureConfiguration {
  let nonce: String
  let receiptPath: String
  let processPath: String
  let phasePath: String
  let logPath: String
  let captureEnabled: Bool

  func sidecar(_ name: String) -> String {
    processPath + ".observer-" + name
  }

  func matches(_ host: HostConfiguration) -> Bool {
    nonce == host.nonce && receiptPath == host.receiptPath
      && processPath == host.processPath && phasePath == host.phasePath
      && logPath == host.logPath && captureEnabled == host.captureEnabled
  }

  static func read(at path: String) throws -> ExitCaptureConfiguration {
    guard let file = try ExitCaptureFiles.read(at: path, limit: 4_096),
      file.data.last == 0
    else {
      throw ExitCaptureFailure.unavailable
    }
    let fields = file.data.split(separator: 0, omittingEmptySubsequences: false)
    guard (fields.count == 6 || fields.count == 7), fields.last?.isEmpty == true else {
      throw ExitCaptureFailure.unavailable
    }
    var values: [String] = []
    for field in fields.dropLast() {
      guard let value = String(data: Data(field), encoding: .utf8) else {
        throw ExitCaptureFailure.unavailable
      }
      values.append(value)
    }
    guard values.count == 5 || values.count == 6,
      UUID(uuidString: values[0]) != nil,
      values.prefix(5).allSatisfy({ !$0.isEmpty && !$0.contains("\n") && !$0.contains("\r") })
    else {
      throw ExitCaptureFailure.unavailable
    }
    let captureEnabled: Bool
    if values.count == 6 {
      guard values[5] == "exit-observer-v1" else {
        throw ExitCaptureFailure.unavailable
      }
      captureEnabled = true
    } else {
      captureEnabled = false
    }
    return ExitCaptureConfiguration(
      nonce: values[0],
      receiptPath: values[1],
      processPath: values[2],
      phasePath: values[3],
      logPath: values[4],
      captureEnabled: captureEnabled
    )
  }
}

private enum ExitCaptureRecord {
  static func data(_ fields: [String]) -> Data {
    Data((fields.joined(separator: "\t") + "\n").utf8)
  }

  static func fields(_ data: Data, limit: Int = ExitCaptureFiles.recordLimit) -> [String]? {
    guard data.count <= limit, data.last == 10,
      let text = String(data: data, encoding: .utf8), !text.contains("\r")
    else {
      return nil
    }
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    guard lines.count == 2, lines.last?.isEmpty == true else { return nil }
    let values = lines[0].split(separator: "\t", omittingEmptySubsequences: false)
      .map(String.init)
    guard values.allSatisfy({ !$0.isEmpty }) else { return nil }
    return values
  }

  static func fields(
    _ data: Data,
    kind: String,
    nonce: String,
    count: Int,
    limit: Int = ExitCaptureFiles.recordLimit
  ) -> [String]? {
    guard let fields = fields(data, limit: limit), fields.count == count,
      fields[0] == kind, fields[1] == nonce
    else {
      return nil
    }
    return fields
  }

  static func lines(_ data: Data) -> [[String]]? {
    guard data.count <= ExitCaptureFiles.evidenceByteLimit, data.last == 10,
      let text = String(data: data, encoding: .utf8), !text.contains("\r")
    else {
      return nil
    }
    let rawLines = text.split(separator: "\n", omittingEmptySubsequences: false)
    guard rawLines.count >= 2, rawLines.count <= ExitCaptureFiles.evidenceRecordLimit + 1,
      rawLines.last?.isEmpty == true
    else {
      return nil
    }
    var result: [[String]] = []
    for line in rawLines.dropLast() {
      let values = line.split(separator: "\t", omittingEmptySubsequences: false)
        .map(String.init)
      guard !values.isEmpty, values.allSatisfy({ !$0.isEmpty }),
        line.utf8.count + 1 <= ExitCaptureFiles.recordLimit
      else {
        return nil
      }
      result.append(values)
    }
    return result
  }

  static func unsigned(_ value: String) -> UInt64? {
    guard !value.isEmpty, value.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
      let number = UInt64(value), String(number) == value
    else {
      return nil
    }
    return number
  }

  static func signed(_ value: String) -> Int64? {
    guard !value.isEmpty else { return nil }
    let digits = value.first == "-" ? value.dropFirst() : value[...]
    guard !digits.isEmpty, digits.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
      let number = Int64(value), String(number) == value
    else {
      return nil
    }
    return number
  }

  static func signal(_ data: Data, kind: String, nonce: String) -> UInt64? {
    guard let fields = fields(data, kind: kind, nonce: nonce, count: 3),
      let ticks = unsigned(fields[2])
    else {
      return nil
    }
    return ticks
  }

  static func acknowledgement(
    _ data: Data,
    identity: ExitCaptureIdentity
  ) -> (deadlineTicks: UInt64, acknowledgedAtTicks: UInt64)? {
    guard let fields = fields(
      data, kind: "ack-v1", nonce: identity.nonce, count: 12
    ),
      unsigned(fields[2]) == identity.pid,
      unsigned(fields[3]) == identity.effectiveUID,
      unsigned(fields[4]) == identity.realUID,
      unsigned(fields[5]) == identity.savedUID,
      unsigned(fields[6]) == identity.startSeconds,
      unsigned(fields[7]) == identity.startMicroseconds,
      let deadline = unsigned(fields[8]),
      let acknowledgedAt = unsigned(fields[9]),
      unsigned(fields[10]) == identity.markerIdentity.device,
      unsigned(fields[11]) == identity.markerIdentity.inode
    else {
      return nil
    }
    return (deadline, acknowledgedAt)
  }

  static func kernelEvent(_ fields: [String], kind: String, nonce: String) -> Bool {
    fields.count == 9 && fields[0] == kind && fields[1] == nonce
      && unsigned(fields[2]) != nil && unsigned(fields[3]) != nil
      && Int16(fields[4]).map({ String($0) == fields[4] }) == true
      && UInt16(fields[5]).map({ String($0) == fields[5] }) == true
      && UInt32(fields[6]).map({ String($0) == fields[6] }) == true
      && signed(fields[7]) != nil && unsigned(fields[8]) != nil
  }

  static func kernelEvent(
    _ event: kevent64_s,
    kind: String,
    nonce: String,
    observedAt: UInt64
  ) -> [String] {
    [
      kind, nonce, String(observedAt), String(event.ident), String(event.filter),
      String(event.flags), String(event.fflags), String(event.data), String(event.udata),
    ]
  }

  static func evidence(_ data: Data, nonce: String) -> [[String]]? {
    guard let records = lines(data), records.count <= ExitCaptureFiles.evidenceRecordLimit else {
      return nil
    }
    var hasRegistration = false
    var hasTerminalObservation = false
    for fields in records {
      switch fields[0] {
      case "registration-v1":
        guard !hasRegistration, kernelEvent(fields, kind: "registration-v1", nonce: nonce) else {
          return nil
        }
        hasRegistration = true
      case "event-v1":
        guard !hasTerminalObservation, kernelEvent(fields, kind: "event-v1", nonce: nonce) else {
          return nil
        }
        hasTerminalObservation = true
      case "alive-v1":
        guard !hasTerminalObservation, fields.count == 5, fields[1] == nonce,
          unsigned(fields[2]) != nil, let pid = unsigned(fields[3]), pid > 0,
          let processStatus = UInt32(fields[4]), String(processStatus) == fields[4]
        else {
          return nil
        }
        hasTerminalObservation = true
      default:
        return nil
      }
    }
    return records
  }

  static func terminal(_ data: Data, nonce: String) -> [String]? {
    guard let fields = fields(data, kind: "terminal-v1", nonce: nonce, count: 8),
      ["exit", "alive", "unavailable"].contains(fields[2]),
      unsigned(fields[3]) != nil,
      unsigned(fields[5]) != nil,
      unsigned(fields[6]) != nil,
      let startMicroseconds = unsigned(fields[7]), startMicroseconds < 1_000_000,
      (fields[2] == "unavailable"
        ? ["clock", "identity", "registration", "ack", "timeout", "stop", "boundary", "event", "snapshot", "evidence", "io"].contains(fields[4])
        : fields[4] == "none")
    else {
      return nil
    }
    return fields
  }

  static func terminalRecord(
    nonce: String,
    status: String,
    observedAt: UInt64,
    reason: String,
    pid: UInt64,
    startSeconds: UInt64,
    startMicroseconds: UInt64
  ) -> [String] {
    [
      "terminal-v1", nonce, status, String(observedAt), reason, String(pid),
      String(startSeconds), String(startMicroseconds),
    ]
  }

  static func outputLine(_ fields: [String]) -> String {
    let label = fields[0] == "registration-v1" ? "registration"
      : fields[0] == "event-v1" ? "event" : "alive"
    return "FLECK_CAPTURE_OBSERVER \(label) \(fields.dropFirst(2).joined(separator: " "))"
  }
}

private struct ExitCaptureClock {
  let nonce: String
  let startTicks: UInt64
  let deadlineTicks: UInt64
  let timebaseNumerator: UInt32
  let timebaseDenominator: UInt32
  let producerPID: UInt64
  let producerEffectiveUID: UInt64
  let producerRealUID: UInt64
  let producerSavedUID: UInt64
  let producerStartSeconds: UInt64
  let producerStartMicroseconds: UInt64

  var producerBinding: String {
    [
      producerPID, producerEffectiveUID, producerRealUID, producerSavedUID,
      producerStartSeconds, producerStartMicroseconds,
    ].map { String($0) }.joined(separator: ":")
  }

  func matchesProducer(_ snapshot: ExitCaptureProcessSnapshot, expectedExecutablePath: String) -> Bool {
    snapshot.pid == producerPID && snapshot.effectiveUID == producerEffectiveUID
      && snapshot.realUID == producerRealUID && snapshot.savedUID == producerSavedUID
      && snapshot.startSeconds == producerStartSeconds
      && snapshot.startMicroseconds == producerStartMicroseconds
      && snapshot.executablePath == expectedExecutablePath && snapshot.status != UInt32(SZOMB)
  }

  static func now() -> UInt64? {
    let ticks = mach_continuous_time()
    guard ticks <= UInt64(Int64.max) else { return nil }
    return ticks
  }

  static func timebase() -> (numerator: UInt32, denominator: UInt32)? {
    var value = mach_timebase_info_data_t()
    guard mach_timebase_info(&value) == KERN_SUCCESS, value.numer > 0, value.denom > 0 else {
      return nil
    }
    return (value.numer, value.denom)
  }

  static func ticks(
    forNanoseconds nanoseconds: UInt64,
    numerator: UInt32,
    denominator: UInt32
  ) -> UInt64? {
    guard nanoseconds > 0, numerator > 0, denominator > 0 else { return nil }
    let product = nanoseconds.multipliedFullWidth(by: UInt64(denominator))
    let divisor = UInt64(numerator)
    guard product.high < divisor else { return nil }
    return divisor.dividingFullWidth(product).quotient
  }

  static func nanoseconds(for seconds: Double) -> UInt64? {
    guard seconds.isFinite, seconds > 0, seconds <= 2_700 else { return nil }
    let value = (seconds * 1_000_000_000).rounded(.down)
    guard value.isFinite, value > 0 else { return nil }
    return UInt64(value)
  }

  static func create(
    nonce: String,
    timeoutSeconds: Double,
    expectedExecutablePath: String
  ) -> ExitCaptureClock? {
    guard let startTicks = now(), let timebase = timebase(),
      let timeoutNanoseconds = nanoseconds(for: timeoutSeconds),
      let duration = ticks(
        forNanoseconds: timeoutNanoseconds,
        numerator: timebase.numerator,
        denominator: timebase.denominator
      ),
      let producer = ExitCaptureProcessSnapshot.read(pid: getpid()),
      producer.pid == UInt64(UInt32(getpid())),
      producer.executablePath == expectedExecutablePath, producer.status != UInt32(SZOMB),
      producer.startSeconds > 0, producer.startSeconds <= UInt64(Int64.max),
      producer.startMicroseconds < 1_000_000
    else {
      return nil
    }
    let (deadlineTicks, overflow) = startTicks.addingReportingOverflow(duration)
    guard !overflow, deadlineTicks <= UInt64(Int64.max), deadlineTicks > startTicks else {
      return nil
    }
    return ExitCaptureClock(
      nonce: nonce,
      startTicks: startTicks,
      deadlineTicks: deadlineTicks,
      timebaseNumerator: timebase.numerator,
      timebaseDenominator: timebase.denominator,
      producerPID: producer.pid,
      producerEffectiveUID: producer.effectiveUID,
      producerRealUID: producer.realUID,
      producerSavedUID: producer.savedUID,
      producerStartSeconds: producer.startSeconds,
      producerStartMicroseconds: producer.startMicroseconds
    )
  }

  func record() -> Data {
    ExitCaptureRecord.data([
      "clock-v1", nonce, String(startTicks), String(deadlineTicks),
      String(timebaseNumerator), String(timebaseDenominator),
      String(producerPID), String(producerEffectiveUID), String(producerRealUID),
      String(producerSavedUID), String(producerStartSeconds), String(producerStartMicroseconds),
    ])
  }

  static func parse(_ data: Data, nonce: String) -> ExitCaptureClock? {
    guard let fields = ExitCaptureRecord.fields(
      data, kind: "clock-v1", nonce: nonce, count: 12
    ),
      let start = ExitCaptureRecord.unsigned(fields[2]),
      let deadline = ExitCaptureRecord.unsigned(fields[3]),
      let numerator = ExitCaptureRecord.unsigned(fields[4]), numerator > 0,
      numerator <= UInt64(UInt32.max),
      let denominator = ExitCaptureRecord.unsigned(fields[5]), denominator > 0,
      denominator <= UInt64(UInt32.max),
      start <= UInt64(Int64.max), deadline <= UInt64(Int64.max), deadline > start,
      let producerPID = ExitCaptureRecord.unsigned(fields[6]),
      producerPID > 0, producerPID <= UInt64(Int32.max),
      let effectiveUID = ExitCaptureRecord.unsigned(fields[7]), effectiveUID <= UInt64(UInt32.max),
      let realUID = ExitCaptureRecord.unsigned(fields[8]), realUID <= UInt64(UInt32.max),
      let savedUID = ExitCaptureRecord.unsigned(fields[9]), savedUID <= UInt64(UInt32.max),
      let startSeconds = ExitCaptureRecord.unsigned(fields[10]),
      startSeconds > 0, startSeconds <= UInt64(Int64.max),
      let startMicroseconds = ExitCaptureRecord.unsigned(fields[11]), startMicroseconds < 1_000_000
    else {
      return nil
    }
    return ExitCaptureClock(
      nonce: nonce,
      startTicks: start,
      deadlineTicks: deadline,
      timebaseNumerator: UInt32(numerator),
      timebaseDenominator: UInt32(denominator),
      producerPID: producerPID,
      producerEffectiveUID: effectiveUID,
      producerRealUID: realUID,
      producerSavedUID: savedUID,
      producerStartSeconds: startSeconds,
      producerStartMicroseconds: startMicroseconds
    )
  }

  func durationTicks(forNanoseconds nanoseconds: UInt64) -> UInt64? {
    Self.ticks(
      forNanoseconds: nanoseconds,
      numerator: timebaseNumerator,
      denominator: timebaseDenominator
    )
  }

  static func nanoseconds(
    until deadline: UInt64,
    now: UInt64,
    numerator: UInt32,
    denominator: UInt32
  ) -> UInt64 {
    let remainingTicks = deadline > now ? deadline - now : 0
    guard remainingTicks > 0, numerator > 0, denominator > 0 else { return 0 }
    let product = remainingTicks.multipliedFullWidth(by: UInt64(numerator))
    let maximumProduct = 25_000_000 * UInt64(denominator)
    guard product.high == 0, product.low < maximumProduct else { return 25_000_000 }
    return product.low / UInt64(denominator)
  }
}

private struct ExitCaptureProcessSnapshot: Equatable {
  let pid: UInt64
  let effectiveUID: UInt64
  let realUID: UInt64
  let savedUID: UInt64
  let startSeconds: UInt64
  let startMicroseconds: UInt64
  let status: UInt32
  let executablePath: String

  static func read(pid: pid_t) -> ExitCaptureProcessSnapshot? {
    var information = proc_bsdinfo()
    let expectedSize = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard expectedSize > 0 else { return nil }
    let actualSize = withUnsafeMutablePointer(to: &information) {
      proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, UnsafeMutableRawPointer($0), expectedSize)
    }
    guard actualSize == expectedSize, pid_t(information.pbi_pid) == pid,
      let path = canonicalProcessPath(pid: pid)
    else {
      return nil
    }
    return ExitCaptureProcessSnapshot(
      pid: UInt64(information.pbi_pid),
      effectiveUID: UInt64(information.pbi_uid),
      realUID: UInt64(information.pbi_ruid),
      savedUID: UInt64(information.pbi_svuid),
      startSeconds: UInt64(information.pbi_start_tvsec),
      startMicroseconds: UInt64(information.pbi_start_tvusec),
      status: UInt32(information.pbi_status),
      executablePath: path
    )
  }

  private static func canonicalProcessPath(pid: pid_t) -> String? {
    var bytes = [CChar](repeating: 0, count: Int(PROC_PIDPATHINFO_MAXSIZE))
    let count = bytes.withUnsafeMutableBufferPointer {
      proc_pidpath(pid, $0.baseAddress, UInt32($0.count))
    }
    guard count > 0, Int(count) < bytes.count, bytes.contains(0),
      let path = canonicalPath(String(cString: bytes))
    else {
      return nil
    }
    return path
  }

  static func canonicalPath(_ path: String) -> String? {
    path.withCString { rawPath in
      guard let resolved = Darwin.realpath(rawPath, nil) else { return nil }
      defer { Darwin.free(resolved) }
      return String(cString: resolved)
    }
  }

  func matches(_ identity: ExitCaptureIdentity) -> Bool {
    pid == identity.pid && effectiveUID == identity.effectiveUID
      && realUID == identity.realUID && savedUID == identity.savedUID
      && startSeconds == identity.startSeconds
      && startMicroseconds == identity.startMicroseconds
  }
}

private struct ExitCaptureIdentity {
  let nonce: String
  let pid: UInt64
  let effectiveUID: UInt64
  let realUID: UInt64
  let savedUID: UInt64
  let startSeconds: UInt64
  let startMicroseconds: UInt64
  let publishedAtTicks: UInt64
  let markerIdentity: ExitCaptureFileIdentity

  func record() -> Data {
    ExitCaptureRecord.data([
      "identity-v1", nonce, String(pid), String(effectiveUID), String(realUID),
      String(savedUID), String(startSeconds), String(startMicroseconds),
      String(publishedAtTicks), String(markerIdentity.device), String(markerIdentity.inode),
    ])
  }

  static func parse(_ data: Data, nonce: String) -> ExitCaptureIdentity? {
    guard let fields = ExitCaptureRecord.fields(
      data, kind: "identity-v1", nonce: nonce, count: 11
    ),
      let pid = ExitCaptureRecord.unsigned(fields[2]), pid > 0, pid <= UInt64(Int32.max),
      let effectiveUID = ExitCaptureRecord.unsigned(fields[3]),
      let realUID = ExitCaptureRecord.unsigned(fields[4]),
      let savedUID = ExitCaptureRecord.unsigned(fields[5]),
      let startSeconds = ExitCaptureRecord.unsigned(fields[6]),
      let startMicroseconds = ExitCaptureRecord.unsigned(fields[7]), startMicroseconds < 1_000_000,
      let publishedAtTicks = ExitCaptureRecord.unsigned(fields[8]),
      let device = ExitCaptureRecord.unsigned(fields[9]),
      let inode = ExitCaptureRecord.unsigned(fields[10]), inode > 0
    else {
      return nil
    }
    return ExitCaptureIdentity(
      nonce: nonce,
      pid: pid,
      effectiveUID: effectiveUID,
      realUID: realUID,
      savedUID: savedUID,
      startSeconds: startSeconds,
      startMicroseconds: startMicroseconds,
      publishedAtTicks: publishedAtTicks,
      markerIdentity: ExitCaptureFileIdentity(device: device, inode: inode)
    )
  }

  func matches(_ snapshot: ExitCaptureProcessSnapshot) -> Bool {
    snapshot.matches(self)
  }
}

private struct ExitCaptureObserverProblem: Error {
  let reason: String
  let observedAtTicks: UInt64
}

private enum ExitCaptureObserver {
  static func run(
    configurationPath: String,
    expectedHostBinary: String,
    timeoutSeconds: Double
  ) -> CInt {
    guard timeoutSeconds.isFinite, timeoutSeconds > 0, timeoutSeconds <= 2_700,
      let expectedPath = canonicalPath(expectedHostBinary)
    else {
      return 1
    }
    let configuration: ExitCaptureConfiguration
    do {
      configuration = try ExitCaptureConfiguration.read(at: configurationPath)
    } catch {
      return 1
    }
    guard configuration.captureEnabled,
      let clock = ExitCaptureClock.create(
        nonce: configuration.nonce, timeoutSeconds: timeoutSeconds,
        expectedExecutablePath: expectedPath
      )
    else {
      return 1
    }
    do {
      try ExitCaptureFiles.writeOnce(
        at: configuration.sidecar("clock"), contents: clock.record(),
        limit: ExitCaptureFiles.recordLimit
      )
    } catch {
      return 1
    }

    var evidence: [[String]] = []
    var terminal: [String]
    do {
      terminal = try observe(
        configuration: configuration,
        clock: clock,
        expectedHostPath: expectedPath,
        evidence: &evidence
      )
    } catch let problem as ExitCaptureObserverProblem {
      terminal = ExitCaptureRecord.terminalRecord(
        nonce: configuration.nonce, status: "unavailable",
        observedAt: problem.observedAtTicks, reason: problem.reason,
        pid: 0, startSeconds: 0, startMicroseconds: 0
      )
    } catch {
      terminal = ExitCaptureRecord.terminalRecord(
        nonce: configuration.nonce, status: "unavailable",
        observedAt: ExitCaptureClock.now() ?? 0, reason: "io",
        pid: 0, startSeconds: 0, startMicroseconds: 0
      )
    }

    var evidenceData: Data?
    if !evidence.isEmpty {
      let candidate = evidence.reduce(into: Data()) { $0.append(ExitCaptureRecord.data($1)) }
      if candidate.count <= ExitCaptureFiles.evidenceByteLimit,
        let records = ExitCaptureRecord.evidence(candidate, nonce: configuration.nonce),
        records.count == evidence.count
      {
        evidenceData = candidate
      } else {
        evidence.removeAll(keepingCapacity: false)
        terminal = ExitCaptureRecord.terminalRecord(
          nonce: configuration.nonce, status: "unavailable",
          observedAt: ExitCaptureClock.now() ?? clock.deadlineTicks, reason: "evidence",
          pid: ExitCaptureRecord.unsigned(terminal[5]) ?? 0,
          startSeconds: ExitCaptureRecord.unsigned(terminal[6]) ?? 0,
          startMicroseconds: ExitCaptureRecord.unsigned(terminal[7]) ?? 0
        )
      }
    }
    do {
      if let evidenceData {
        try ExitCaptureFiles.writeOnce(
          at: configuration.sidecar("evidence"), contents: evidenceData,
          limit: ExitCaptureFiles.evidenceByteLimit
        )
      }
      try ExitCaptureFiles.writeOnce(
        at: configuration.sidecar("terminal"), contents: ExitCaptureRecord.data(terminal),
        limit: ExitCaptureFiles.recordLimit
      )
      return terminal[2] == "unavailable" ? 1 : 0
    } catch {
      return 1
    }
  }

  private static func observe(
    configuration: ExitCaptureConfiguration,
    clock: ExitCaptureClock,
    expectedHostPath: String,
    evidence: inout [[String]]
  ) throws -> [String] {
    guard let identityFile = try waitForIdentity(configuration: configuration, clock: clock) else {
      throw problem("timeout", clock: clock)
    }
    guard let identity = ExitCaptureIdentity.parse(identityFile.data, nonce: configuration.nonce),
      identity.publishedAtTicks >= clock.startTicks,
      identity.publishedAtTicks < clock.deadlineTicks
    else {
      throw problem("identity", clock: clock)
    }
    let markerFile = try readMarker(configuration: configuration, pid: identity.pid)
    guard markerFile.identity == identity.markerIdentity,
      let initialSnapshot = ExitCaptureProcessSnapshot.read(pid: pid_t(identity.pid)),
      identity.matches(initialSnapshot), initialSnapshot.executablePath == expectedHostPath,
      initialSnapshot.status != UInt32(SZOMB)
    else {
      throw problem("identity", clock: clock)
    }

    let queue = kqueue()
    guard queue >= 0 else { throw problem("registration", clock: clock) }
    defer { _ = Darwin.close(queue) }
    let cookie = (clock.startTicks ^ (identity.pid &* 0x9e3779b97f4a7c15)) | 1
    var change = kevent64_s()
    change.ident = identity.pid
    change.filter = Int16(EVFILT_PROC)
    change.flags = UInt16(EV_ADD | EV_ENABLE | EV_RECEIPT)
    change.fflags = UInt32(NOTE_EXIT | NOTE_EXITSTATUS)
    change.data = 0
    change.udata = cookie
    var receipt = kevent64_s()
    let receiptCount = kevent64(queue, &change, 1, &receipt, 1, 0, nil)
    let receiptAt = ExitCaptureClock.now() ?? 0
    guard receiptCount == 1 else { throw problem("registration", clock: clock, at: receiptAt) }
    evidence.append(ExitCaptureRecord.kernelEvent(
      receipt, kind: "registration-v1", nonce: configuration.nonce, observedAt: receiptAt
    ))
    guard receiptAt >= identity.publishedAtTicks, receiptAt < clock.deadlineTicks,
      receipt.ident == identity.pid, receipt.filter == Int16(EVFILT_PROC), receipt.udata == cookie,
      receipt.flags & UInt16(EV_ERROR) != 0, receipt.data == 0
    else {
      throw problem("registration", clock: clock, at: receiptAt)
    }

    guard let ackDuration = clock.durationTicks(forNanoseconds: 1_000_000_000),
      let ackDeadline = boundedDeadline(start: identity.publishedAtTicks, duration: ackDuration, clock: clock)
    else {
      throw problem("ack", clock: clock)
    }
    guard try revalidateHost(
      configuration: configuration,
      clock: clock,
      identity: identity,
      identityFileIdentity: identityFile.identity,
      markerFileIdentity: markerFile.identity,
      expectedHostPath: expectedHostPath
    ) else {
      throw problem("identity", clock: clock)
    }
    if try readSignal(configuration: configuration, name: "stop", kind: "stop-v1") != nil {
      throw problem("stop", clock: clock)
    }
    if try readSignal(configuration: configuration, name: "boundary", kind: "boundary-v1") != nil {
      throw problem("boundary", clock: clock)
    }
    let ackAt = ExitCaptureClock.now() ?? 0
    guard ackAt >= receiptAt, ackAt < ackDeadline, ackAt < clock.deadlineTicks else {
      throw problem("ack", clock: clock, at: ackAt)
    }
    do {
      try ExitCaptureFiles.writeOnce(
        at: configuration.sidecar("ack"),
        contents: ExitCaptureRecord.data([
          "ack-v1", identity.nonce, String(identity.pid), String(identity.effectiveUID),
          String(identity.realUID), String(identity.savedUID), String(identity.startSeconds),
          String(identity.startMicroseconds), String(clock.deadlineTicks), String(ackAt),
          String(identity.markerIdentity.device), String(identity.markerIdentity.inode),
        ]),
        limit: ExitCaptureFiles.recordLimit
      )
    } catch {
      throw problem("ack", clock: clock, at: ackAt)
    }

    while true {
      let now = ExitCaptureClock.now() ?? 0
      if now >= clock.deadlineTicks {
        throw problem("timeout", clock: clock, at: now)
      }
      let stop = try readSignal(configuration: configuration, name: "stop", kind: "stop-v1")
      let boundary = try readSignal(
        configuration: configuration, name: "boundary", kind: "boundary-v1"
      )
      if let stop, stop > clock.deadlineTicks {
        throw problem("stop", clock: clock, at: stop)
      }
      if let boundary, boundary > clock.deadlineTicks {
        throw problem("boundary", clock: clock, at: boundary)
      }

      let shouldDrain = stop != nil || boundary != nil
      var event = kevent64_s()
      var timeout = timespec()
      if shouldDrain {
        timeout.tv_sec = 0
        timeout.tv_nsec = 0
      } else {
        timeout.tv_sec = 0
        timeout.tv_nsec = Int(ExitCaptureClock.nanoseconds(
          until: clock.deadlineTicks, now: now,
          numerator: clock.timebaseNumerator, denominator: clock.timebaseDenominator
        ))
      }
      let eventCount = kevent64(queue, nil, 0, &event, 1, 0, &timeout)
      if eventCount < 0 {
        if errno == EINTR && !shouldDrain { continue }
        throw problem("event", clock: clock)
      }
      if eventCount == 1 {
        let observedAt = ExitCaptureClock.now() ?? 0
        evidence.append(ExitCaptureRecord.kernelEvent(
          event, kind: "event-v1", nonce: configuration.nonce, observedAt: observedAt
        ))
        let currentBoundary = try readSignal(
          configuration: configuration, name: "boundary", kind: "boundary-v1"
        )
        let eventIsValid = event.ident == identity.pid
          && event.filter == Int16(EVFILT_PROC) && event.udata == cookie
          && event.flags & UInt16(EV_ERROR) == 0
          && event.fflags & UInt32(NOTE_EXIT) != 0
          && event.fflags & UInt32(NOTE_EXITSTATUS) != 0
        guard eventIsValid, observedAt >= ackAt, observedAt < clock.deadlineTicks,
          boundary.map({ observedAt < $0 }) ?? true,
          currentBoundary.map({ observedAt < $0 }) ?? true
        else {
          throw problem("event", clock: clock, at: observedAt)
        }
        return terminal(
          status: "exit", reason: "none", observedAt: observedAt, identity: identity
        )
      }

      if shouldDrain {
        guard try revalidateHost(
            configuration: configuration,
            clock: clock,
            identity: identity,
            identityFileIdentity: identityFile.identity,
            markerFileIdentity: markerFile.identity,
            expectedHostPath: expectedHostPath
          ),
          let snapshot = ExitCaptureProcessSnapshot.read(pid: pid_t(identity.pid)),
          identity.matches(snapshot), snapshot.executablePath == expectedHostPath,
          snapshot.status != UInt32(SZOMB)
        else {
          throw problem("snapshot", clock: clock)
        }
        let currentBoundary = try readSignal(
          configuration: configuration, name: "boundary", kind: "boundary-v1"
        )
        guard let snapshotAt = ExitCaptureClock.now(),
          snapshotAt >= ackAt, snapshotAt < clock.deadlineTicks,
          boundary.map({ snapshotAt < $0 }) ?? true,
          currentBoundary.map({ snapshotAt < $0 }) ?? true
        else {
          throw problem("snapshot", clock: clock)
        }
        evidence.append([
          "alive-v1", identity.nonce, String(snapshotAt), String(identity.pid),
          String(snapshot.status),
        ])
        return terminal(
          status: "alive", reason: "none", observedAt: snapshotAt, identity: identity
        )
      }

      if now >= clock.deadlineTicks {
        throw problem("timeout", clock: clock, at: now)
      }
    }
  }

  private static func waitForIdentity(
    configuration: ExitCaptureConfiguration,
    clock: ExitCaptureClock
  ) throws -> ExitCaptureFile? {
    while let now = ExitCaptureClock.now(), now < clock.deadlineTicks {
      if try readSignal(configuration: configuration, name: "stop", kind: "stop-v1") != nil {
        throw problem("stop", clock: clock, at: now)
      }
      if try readSignal(configuration: configuration, name: "boundary", kind: "boundary-v1") != nil {
        throw problem("boundary", clock: clock, at: now)
      }
      if let identity = try ExitCaptureFiles.read(
        at: configuration.sidecar("identity"), limit: ExitCaptureFiles.recordLimit,
        allowMissing: true
      ) {
        return identity
      }
      usleep(25_000)
    }
    return nil
  }

  private static func readMarker(
    configuration: ExitCaptureConfiguration,
    pid: UInt64
  ) throws -> ExitCaptureFile {
    guard let marker = try ExitCaptureFiles.read(
      at: configuration.processPath, limit: ExitCaptureFiles.recordLimit
    ), marker.data == Data("\(configuration.nonce)\t\(pid)\n".utf8)
    else {
      throw ExitCaptureFailure.unavailable
    }
    return marker
  }

  private static func revalidateHost(
    configuration: ExitCaptureConfiguration,
    clock: ExitCaptureClock,
    identity: ExitCaptureIdentity,
    identityFileIdentity: ExitCaptureFileIdentity,
    markerFileIdentity: ExitCaptureFileIdentity,
    expectedHostPath: String
  ) throws -> Bool {
    guard let identityFile = try ExitCaptureFiles.read(
      at: configuration.sidecar("identity"), limit: ExitCaptureFiles.recordLimit
    ), identityFile.identity == identityFileIdentity,
      ExitCaptureIdentity.parse(identityFile.data, nonce: configuration.nonce)?.pid == identity.pid,
      identityFile.data == identity.record(),
      let marker = try? readMarker(configuration: configuration, pid: identity.pid),
      marker.identity == markerFileIdentity,
      let snapshot = ExitCaptureProcessSnapshot.read(pid: pid_t(identity.pid)),
      identity.matches(snapshot), snapshot.executablePath == expectedHostPath,
      snapshot.status != UInt32(SZOMB),
      let now = ExitCaptureClock.now(), now < clock.deadlineTicks
    else {
      return false
    }
    return true
  }

  private static func readSignal(
    configuration: ExitCaptureConfiguration,
    name: String,
    kind: String
  ) throws -> UInt64? {
    guard let file = try ExitCaptureFiles.read(
      at: configuration.sidecar(name), limit: ExitCaptureFiles.recordLimit,
      allowMissing: true
    ) else {
      return nil
    }
    guard let ticks = ExitCaptureRecord.signal(file.data, kind: kind, nonce: configuration.nonce) else {
      throw ExitCaptureFailure.unavailable
    }
    return ticks
  }

  private static func terminal(
    status: String,
    reason: String,
    observedAt: UInt64,
    identity: ExitCaptureIdentity
  ) -> [String] {
    ExitCaptureRecord.terminalRecord(
      nonce: identity.nonce, status: status, observedAt: observedAt, reason: reason,
      pid: identity.pid, startSeconds: identity.startSeconds,
      startMicroseconds: identity.startMicroseconds
    )
  }

  private static func problem(
    _ reason: String,
    clock: ExitCaptureClock,
    at ticks: UInt64? = nil
  ) -> ExitCaptureObserverProblem {
    ExitCaptureObserverProblem(
      reason: reason,
      observedAtTicks: ticks ?? ExitCaptureClock.now() ?? clock.deadlineTicks
    )
  }

  private static func boundedDeadline(
    start: UInt64,
    duration: UInt64,
    clock: ExitCaptureClock
  ) -> UInt64? {
    let (candidate, overflow) = start.addingReportingOverflow(duration)
    guard !overflow else { return nil }
    return Swift.min(candidate, clock.deadlineTicks)
  }

  private static func canonicalPath(_ path: String) -> String? {
    guard path.hasPrefix("/"), !path.utf8.contains(0) else { return nil }
    return path.withCString { rawPath in
      guard let resolved = Darwin.realpath(rawPath, nil) else { return nil }
      defer { Darwin.free(resolved) }
      return String(cString: resolved)
    }
  }
}

private enum ExitCaptureHost {
  static func publishAndAwait(
    configurationPath: String,
    hostConfiguration: HostConfiguration
  ) async throws {
    let configuration = try ExitCaptureConfiguration.read(at: configurationPath)
    guard configuration.captureEnabled, configuration.matches(hostConfiguration),
      let clockFile = try ExitCaptureFiles.read(
        at: configuration.sidecar("clock"), limit: ExitCaptureFiles.recordLimit
      ),
      let clock = ExitCaptureClock.parse(clockFile.data, nonce: configuration.nonce),
      let waitStart = ExitCaptureClock.now(), waitStart < clock.deadlineTicks,
      let waitDuration = clock.durationTicks(forNanoseconds: 1_000_000_000),
      let waitDeadline = boundedDeadline(start: waitStart, duration: waitDuration, clock: clock),
      let snapshot = ExitCaptureProcessSnapshot.read(pid: getpid()),
      snapshot.pid == UInt64(UInt32(getpid())), snapshot.executablePath.count > 0,
      let producer = ExitCaptureProcessSnapshot.read(pid: pid_t(clock.producerPID)),
      clock.matchesProducer(producer, expectedExecutablePath: snapshot.executablePath),
      let marker = try ExitCaptureFiles.read(
        at: configuration.processPath, limit: ExitCaptureFiles.recordLimit
      ), marker.data == Data("\(configuration.nonce)\t\(getpid())\n".utf8)
    else {
      throw ExitCaptureFailure.unavailable
    }
    let identity = ExitCaptureIdentity(
      nonce: configuration.nonce,
      pid: snapshot.pid,
      effectiveUID: snapshot.effectiveUID,
      realUID: snapshot.realUID,
      savedUID: snapshot.savedUID,
      startSeconds: snapshot.startSeconds,
      startMicroseconds: snapshot.startMicroseconds,
      publishedAtTicks: waitStart,
      markerIdentity: marker.identity
    )
    guard snapshot.status != UInt32(SZOMB) else { throw ExitCaptureFailure.unavailable }
    try ExitCaptureFiles.writeOnce(
      at: configuration.sidecar("identity"), contents: identity.record(),
      limit: ExitCaptureFiles.recordLimit
    )

    while let now = ExitCaptureClock.now(), now < waitDeadline {
      if let ackFile = try ExitCaptureFiles.read(
        at: configuration.sidecar("ack"), limit: ExitCaptureFiles.recordLimit,
        allowMissing: true
      ) {
        guard let ack = ExitCaptureRecord.acknowledgement(ackFile.data, identity: identity),
          ack.deadlineTicks == clock.deadlineTicks,
          ack.acknowledgedAtTicks >= waitStart,
          ack.acknowledgedAtTicks < waitDeadline,
          let currentMarker = try ExitCaptureFiles.read(
            at: configuration.processPath, limit: ExitCaptureFiles.recordLimit
          ), currentMarker.identity == marker.identity,
          currentMarker.data == marker.data,
          let currentSnapshot = ExitCaptureProcessSnapshot.read(pid: getpid()),
          identity.matches(currentSnapshot), currentSnapshot.executablePath == snapshot.executablePath,
          currentSnapshot.status != UInt32(SZOMB),
          try ExitCaptureFiles.read(
            at: configuration.sidecar("stop"), limit: ExitCaptureFiles.recordLimit,
            allowMissing: true
          ) == nil,
          try ExitCaptureFiles.read(
            at: configuration.sidecar("boundary"), limit: ExitCaptureFiles.recordLimit,
            allowMissing: true
          ) == nil,
          let currentClockFile = try ExitCaptureFiles.read(
            at: configuration.sidecar("clock"), limit: ExitCaptureFiles.recordLimit
          ), currentClockFile.identity == clockFile.identity,
          currentClockFile.data == clockFile.data,
          let currentProducer = ExitCaptureProcessSnapshot.read(pid: pid_t(clock.producerPID)),
          clock.matchesProducer(currentProducer, expectedExecutablePath: snapshot.executablePath),
          let acceptedAt = ExitCaptureClock.now(),
          acceptedAt >= ack.acknowledgedAtTicks,
          acceptedAt < waitDeadline, acceptedAt < clock.deadlineTicks
        else {
          throw ExitCaptureFailure.unavailable
        }
        return
      }
      let remaining = waitDeadline > now ? waitDeadline - now : 0
      let sleepNanoseconds = ExitCaptureClock.nanoseconds(
        until: waitDeadline, now: now,
        numerator: clock.timebaseNumerator, denominator: clock.timebaseDenominator
      )
      guard remaining > 0 else { break }
      do {
        try await Task.sleep(for: .nanoseconds(Int64(sleepNanoseconds)))
      } catch {
        throw ExitCaptureFailure.unavailable
      }
    }
    throw ExitCaptureFailure.unavailable
  }

  private static func boundedDeadline(start: UInt64, duration: UInt64, clock: ExitCaptureClock) -> UInt64? {
    let (candidate, overflow) = start.addingReportingOverflow(duration)
    guard !overflow else { return nil }
    return Swift.min(candidate, clock.deadlineTicks)
  }
}

private enum ExitCaptureCLI {
  static func run(_ arguments: [String]) -> CInt {
    guard let operation = arguments.first else { return unavailable() }
    let values = Array(arguments.dropFirst())
    switch operation {
    case "run":
      guard values.count == 3, let timeout = Double(values[2]) else { return 1 }
      return ExitCaptureObserver.run(
        configurationPath: values[0], expectedHostBinary: values[1], timeoutSeconds: timeout
      )
    case "ready":
      guard values.count == 3 else { return unavailable() }
      return ready(
        configurationPath: values[0], expectedObserverPID: values[1],
        expectedObserverBinary: values[2]
      )
    case "clock":
      guard values.isEmpty, let now = ExitCaptureClock.now() else { return 1 }
      output(String(now))
      return 0
    case "stop", "boundary":
      guard values.count == 1 else { return unavailable() }
      return writeSignal(configurationPath: values[0], kind: operation)
    case "drain":
      guard values.count == 5 else { return drainUnavailable() }
      return drain(
        configurationPath: values[0],
        observerWaitStatus: values[1],
        reapedAt: values[2],
        expectedDeadline: values[3], expectedProducerBinding: values[4]
      )
    default:
      return unavailable()
    }
  }

  private static func ready(
    configurationPath: String,
    expectedObserverPID: String,
    expectedObserverBinary: String
  ) -> CInt {
    guard let start = ExitCaptureClock.now() else { return unavailable() }
    let configuration: ExitCaptureConfiguration
    do {
      configuration = try ExitCaptureConfiguration.read(at: configurationPath)
    } catch {
      return unavailable()
    }
    guard configuration.captureEnabled,
      let expectedPID = ExitCaptureRecord.unsigned(expectedObserverPID),
      expectedPID > 0, expectedPID <= UInt64(Int32.max),
      expectedObserverBinary.hasPrefix("/"), !expectedObserverBinary.utf8.contains(0),
      let expectedPath = ExitCaptureProcessSnapshot.canonicalPath(expectedObserverBinary),
      let helper = ExitCaptureProcessSnapshot.read(pid: getpid()),
      helper.executablePath == expectedPath, helper.status != UInt32(SZOMB),
      let timebase = ExitCaptureClock.timebase(),
      let localDuration = ExitCaptureClock.ticks(
        forNanoseconds: 1_000_000_000,
        numerator: timebase.numerator,
        denominator: timebase.denominator
      )
    else {
      return unavailable()
    }
    let (localDeadline, overflow) = start.addingReportingOverflow(localDuration)
    guard !overflow else { return unavailable() }
    while let now = ExitCaptureClock.now(), now <= localDeadline {
      do {
        if let file = try ExitCaptureFiles.read(
          at: configuration.sidecar("clock"), limit: ExitCaptureFiles.recordLimit,
          allowMissing: true
        ) {
          guard let clock = ExitCaptureClock.parse(file.data, nonce: configuration.nonce),
            clock.producerPID == expectedPID,
            let producerBefore = ExitCaptureProcessSnapshot.read(pid: pid_t(expectedPID)),
            clock.matchesProducer(producerBefore, expectedExecutablePath: expectedPath),
            let rebound = try ExitCaptureFiles.read(
              at: configuration.sidecar("clock"), limit: ExitCaptureFiles.recordLimit
            ), rebound.identity == file.identity, rebound.data == file.data,
            let producerAfter = ExitCaptureProcessSnapshot.read(pid: pid_t(expectedPID)),
            clock.matchesProducer(producerAfter, expectedExecutablePath: expectedPath),
            let acceptedAt = ExitCaptureClock.now(),
            acceptedAt < localDeadline, acceptedAt < clock.deadlineTicks
          else {
            return unavailable()
          }
          output("FLECK_CAPTURE_READY \(clock.deadlineTicks) \(clock.producerBinding)")
          return 0
        }
      } catch {
        return unavailable()
      }
      var delay = timespec()
      let delayNanoseconds = ExitCaptureClock.nanoseconds(
        until: localDeadline, now: now,
        numerator: timebase.numerator, denominator: timebase.denominator
      )
      delay.tv_sec = 0
      delay.tv_nsec = Int(delayNanoseconds)
      _ = nanosleep(&delay, nil)
    }
    return unavailable()
  }

  private static func writeSignal(configurationPath: String, kind: String) -> CInt {
    do {
      let configuration = try ExitCaptureConfiguration.read(at: configurationPath)
      guard configuration.captureEnabled, let now = ExitCaptureClock.now() else {
        return unavailable()
      }
      let suffix = kind == "stop" ? "stop" : "boundary"
      let recordKind = kind == "stop" ? "stop-v1" : "boundary-v1"
      let record = ExitCaptureRecord.data([recordKind, configuration.nonce, String(now)])
      try ExitCaptureFiles.writeIdempotently(
        at: configuration.sidecar(suffix), contents: record,
        existingRecordIsValid: {
          guard let ticks = ExitCaptureRecord.signal(
            $0, kind: recordKind, nonce: configuration.nonce
          ) else { return false }
          return ticks <= UInt64(Int64.max)
        }
      )
      return 0
    } catch {
      return unavailable()
    }
  }

  private static func drain(
    configurationPath: String,
    observerWaitStatus: String,
    reapedAt: String,
    expectedDeadline: String,
    expectedProducerBinding: String
  ) -> CInt {
    var deadline: UInt64 = 0
    var lastObserved: UInt64 = 0
    var status = "unavailable"
    var printedEvidence: [String] = []
    var valid = false

    do {
      let configuration = try ExitCaptureConfiguration.read(at: configurationPath)
      guard configuration.captureEnabled,
        let waitStatus = ExitCaptureRecord.unsigned(observerWaitStatus),
        let reapedAtTicks = ExitCaptureRecord.unsigned(reapedAt), reapedAtTicks > 0,
        let expectedDeadlineTicks = ExitCaptureRecord.unsigned(expectedDeadline),
        expectedDeadlineTicks > 0,
        let clockFile = try ExitCaptureFiles.read(
          at: configuration.sidecar("clock"), limit: ExitCaptureFiles.recordLimit
        ),
        let clock = ExitCaptureClock.parse(clockFile.data, nonce: configuration.nonce),
        clock.deadlineTicks == expectedDeadlineTicks,
        clock.producerBinding == expectedProducerBinding,
        let identityFile = try ExitCaptureFiles.read(
          at: configuration.sidecar("identity"), limit: ExitCaptureFiles.recordLimit
        ),
        let identity = ExitCaptureIdentity.parse(identityFile.data, nonce: configuration.nonce),
        let ackFile = try ExitCaptureFiles.read(
          at: configuration.sidecar("ack"), limit: ExitCaptureFiles.recordLimit
        ),
        let ack = ExitCaptureRecord.acknowledgement(ackFile.data, identity: identity),
        let boundaryFile = try ExitCaptureFiles.read(
          at: configuration.sidecar("boundary"), limit: ExitCaptureFiles.recordLimit
        ),
        let boundary = ExitCaptureRecord.signal(
          boundaryFile.data, kind: "boundary-v1", nonce: configuration.nonce
        ),
        let terminalFile = try ExitCaptureFiles.read(
          at: configuration.sidecar("terminal"), limit: ExitCaptureFiles.recordLimit
        ),
        let terminal = ExitCaptureRecord.terminal(terminalFile.data, nonce: configuration.nonce),
        let terminalAt = ExitCaptureRecord.unsigned(terminal[3]),
        let terminalPID = ExitCaptureRecord.unsigned(terminal[5]),
        let terminalStartSeconds = ExitCaptureRecord.unsigned(terminal[6]),
        let terminalStartMicroseconds = ExitCaptureRecord.unsigned(terminal[7]),
        let marker = try ExitCaptureFiles.read(
          at: configuration.processPath, limit: ExitCaptureFiles.recordLimit
        ),
        marker.identity == identity.markerIdentity,
        marker.data == Data("\(configuration.nonce)\t\(identity.pid)\n".utf8),
        identity.publishedAtTicks >= clock.startTicks,
        identity.publishedAtTicks < clock.deadlineTicks,
        ack.deadlineTicks == clock.deadlineTicks,
        ack.acknowledgedAtTicks >= identity.publishedAtTicks,
        ack.acknowledgedAtTicks < clock.deadlineTicks,
        let ackDuration = clock.durationTicks(forNanoseconds: 1_000_000_000),
        ack.acknowledgedAtTicks - identity.publishedAtTicks < ackDuration,
        terminalPID == identity.pid,
        terminalStartSeconds == identity.startSeconds,
        terminalStartMicroseconds == identity.startMicroseconds,
        boundary <= UInt64(Int64.max),
        let evidenceFile = try ExitCaptureFiles.read(
          at: configuration.sidecar("evidence"), limit: ExitCaptureFiles.evidenceByteLimit
        ),
        let evidence = ExitCaptureRecord.evidence(evidenceFile.data, nonce: configuration.nonce)
      else {
        throw ExitCaptureFailure.unavailable
      }

      deadline = clock.deadlineTicks
      status = terminal[2]
      lastObserved = terminalAt
      printedEvidence = evidence.map { ExitCaptureRecord.outputLine($0) }

      let registration = evidence.first { $0[0] == "registration-v1" }
      let exitEvent = evidence.first { $0[0] == "event-v1" }
      let alive = evidence.first { $0[0] == "alive-v1" }
      let cookie = (clock.startTicks ^ (identity.pid &* 0x9e3779b97f4a7c15)) | 1
      let registrationIsValid = registration.map { fields -> Bool in
        guard let observedAt = ExitCaptureRecord.unsigned(fields[2]),
          let ident = ExitCaptureRecord.unsigned(fields[3]),
          let filter = Int16(fields[4]), String(filter) == fields[4],
          let flags = UInt16(fields[5]), String(flags) == fields[5],
          let data = ExitCaptureRecord.signed(fields[7]),
          let eventCookie = ExitCaptureRecord.unsigned(fields[8])
        else {
          return false
        }
        return observedAt >= identity.publishedAtTicks
          && observedAt <= ack.acknowledgedAtTicks && ident == identity.pid
          && filter == Int16(EVFILT_PROC) && eventCookie == cookie
          && flags & UInt16(EV_ERROR) != 0 && data == 0
      } ?? false
      let exitIsValid = exitEvent.map { fields -> Bool in
        guard let observedAt = ExitCaptureRecord.unsigned(fields[2]),
          let ident = ExitCaptureRecord.unsigned(fields[3]),
          let filter = Int16(fields[4]), String(filter) == fields[4],
          let flags = UInt16(fields[5]), String(flags) == fields[5],
          let fflags = UInt32(fields[6]), String(fflags) == fields[6],
          let eventCookie = ExitCaptureRecord.unsigned(fields[8])
        else {
          return false
        }
        return ident == identity.pid && filter == Int16(EVFILT_PROC)
          && eventCookie == cookie && flags & UInt16(EV_ERROR) == 0
          && fflags & UInt32(NOTE_EXIT) != 0
          && fflags & UInt32(NOTE_EXITSTATUS) != 0
          && observedAt == terminalAt
      } ?? false
      let aliveIsValid = alive.map { fields -> Bool in
        guard let ticks = ExitCaptureRecord.unsigned(fields[2]),
          let pid = ExitCaptureRecord.unsigned(fields[3]),
          let processStatus = UInt32(fields[4]), String(processStatus) == fields[4]
        else {
          return false
        }
        return ticks == terminalAt && pid == identity.pid && processStatus != UInt32(SZOMB)
      } ?? false
      let stopFile = try ExitCaptureFiles.read(
        at: configuration.sidecar("stop"), limit: ExitCaptureFiles.recordLimit,
        allowMissing: true
      )
      let stopValid: Bool
      if let stopFile {
        stopValid = ExitCaptureRecord.signal(
          stopFile.data, kind: "stop-v1", nonce: configuration.nonce
        ).map({ $0 <= clock.deadlineTicks }) ?? false
      } else {
        stopValid = true
      }
      let evidenceTimes = evidence.compactMap { ExitCaptureRecord.unsigned($0[2]) }
      let allBeforeBounds = identity.publishedAtTicks < clock.deadlineTicks
        && identity.publishedAtTicks < boundary
        && ack.acknowledgedAtTicks < clock.deadlineTicks
        && ack.acknowledgedAtTicks < boundary
        && evidenceTimes.allSatisfy { $0 < clock.deadlineTicks && $0 < boundary }
        && terminalAt >= ack.acknowledgedAtTicks
        && terminalAt < clock.deadlineTicks
        && terminalAt < boundary
        && reapedAtTicks >= terminalAt
        && reapedAtTicks < clock.deadlineTicks
      let matchingTerminal = (terminal[2] == "exit" && terminal[4] == "none" && exitIsValid)
        || (terminal[2] == "alive" && terminal[4] == "none" && aliveIsValid)
      let drainAt = ExitCaptureClock.now() ?? 0
      valid = waitStatus == 0 && registrationIsValid && matchingTerminal && stopValid
        && allBeforeBounds && drainAt >= reapedAtTicks && drainAt < clock.deadlineTicks
      if drainAt == 0 { valid = false }
    } catch {
      status = "unavailable"
    }

    let drainDone = ExitCaptureClock.now() ?? 0
    if drainDone == 0 || drainDone >= deadline { valid = false }
    if !valid && status == "unavailable" { printedEvidence.removeAll(keepingCapacity: false) }
    for line in printedEvidence { output(line) }
    output("FLECK_CAPTURE_DRAIN \(valid ? 1 : 0) \(deadline) \(lastObserved) \(drainDone) \(status)")
    return valid ? 0 : 1
  }

  private static func drainUnavailable() -> CInt {
    let now = ExitCaptureClock.now() ?? 0
    output("FLECK_CAPTURE_DRAIN 0 0 0 \(now) unavailable")
    return 1
  }

  private static func unavailable() -> CInt {
    return 1
  }

  private static func output(_ value: String) {
    FileHandle.standardOutput.write(Data((value + "\n").utf8))
  }
}

@main
struct AppKitTestMain {
  @MainActor
  static func main() async {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.first == "--fleck-exit-observer" {
      Darwin.exit(ExitCaptureCLI.run(Array(arguments.dropFirst())))
    }

    let parsedArguments: ParsedArguments
    do {
      parsedArguments = try parseArguments()
    } catch {
      failBeforeConfiguration("\(error)")
    }

    let configuration: HostConfiguration
    do {
      configuration = try HostConfiguration.read(at: parsedArguments.configurationPath)
      try redirectStandardOutput(to: configuration.logPath)
      try writeHostFile(
        "\(configuration.nonce)\t\(getpid())\n",
        to: configuration.processPath
      )
      configuration.writePhase("starting")
    } catch {
      failBeforeConfiguration("failed to initialize the AppKit test host: \(error)")
    }

    if configuration.captureEnabled {
      do {
        try await ExitCaptureHost.publishAndAwait(
          configurationPath: parsedArguments.configurationPath,
          hostConfiguration: configuration
        )
      } catch {
        configuration.finish(status: 1)
      }
    }

    do {
      try loadTestBundle(at: parsedArguments.bundlePath)
    } catch {
      failAfterConfiguration("\(error)", configuration: configuration)
    }

    if parsedArguments.testingArguments.listTests == true {
      configuration.writePhase("listingTests")
      let status: CInt = await Testing.__swiftPMEntryPoint(
        passing: parsedArguments.testingArguments
      )
      configuration.finish(status: status)
    }

    let application = NSApplication.shared
    let delegate = AppKitTestApplicationDelegate(
      application: application,
      testingArguments: parsedArguments.testingArguments,
      configuration: configuration
    )
    application.delegate = delegate
    application.run()
    delegate.fail("NSApplication.run returned before Swift Testing finished")
  }

  private static func parseArguments() throws -> ParsedArguments {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let bundlePath = arguments.first else {
      throw HostError("usage: AppKitTestHost <test-bundle-binary> [--list-tests] [--filter <regex>] [--no-parallel] --host-config <path>")
    }

    var testingArguments = Testing.__CommandLineArguments_v0()
    var filters: [String] = []
    var configurationPath: String?
    var index = 1
    while index < arguments.count {
      switch arguments[index] {
      case "--list-tests":
        testingArguments.listTests = true
        index += 1
      case "--filter":
        guard index + 1 < arguments.count else {
          throw HostError("missing value for --filter")
        }
        filters.append(arguments[index + 1])
        index += 2
      case "--no-parallel":
        testingArguments.parallel = false
        index += 1
      case "--host-config":
        guard configurationPath == nil, index + 1 < arguments.count else {
          throw HostError("missing or duplicate value for --host-config")
        }
        configurationPath = arguments[index + 1]
        index += 2
      default:
        throw HostError("unsupported test argument: \(arguments[index])")
      }
    }
    guard let configurationPath else {
      throw HostError("missing value for --host-config")
    }
    if !filters.isEmpty {
      testingArguments.filter = filters
    }
    return ParsedArguments(
      bundlePath: bundlePath,
      configurationPath: configurationPath,
      testingArguments: testingArguments
    )
  }

  private static func loadTestBundle(at path: String) throws {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
      !isDirectory.boolValue
    else {
      throw HostError("test bundle binary is missing: \(path)")
    }
    guard dlopen(path, RTLD_NOW | RTLD_GLOBAL) != nil else {
      let detail = dlerror().map { String(cString: $0) } ?? "unknown loader error"
      throw HostError("failed to load test bundle: \(detail)")
    }
  }

  private static func failBeforeConfiguration(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    Darwin.exit(1)
  }

  private static func failAfterConfiguration(
    _ message: String,
    configuration: HostConfiguration
  ) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    configuration.finish(status: 1)
  }

  private static func redirectStandardOutput(to path: String) throws {
    let descriptor = Darwin.open(path, O_WRONLY | O_CREAT | O_TRUNC, mode_t(0o600))
    guard descriptor >= 0 else {
      throw HostError("could not open host log \(path): \(String(cString: strerror(errno)))")
    }
    defer { _ = Darwin.close(descriptor) }
    guard dup2(descriptor, STDOUT_FILENO) >= 0,
      dup2(descriptor, STDERR_FILENO) >= 0
    else {
      throw HostError("could not redirect host output to \(path)")
    }
  }

  private static func writeHostFile(_ contents: String, to path: String) throws {
    try Data(contents.utf8).write(
      to: URL(fileURLWithPath: path),
      options: .atomic
    )
  }
}

private struct ParsedArguments {
  let bundlePath: String
  let configurationPath: String
  let testingArguments: Testing.__CommandLineArguments_v0
}

private struct HostConfiguration {
  let nonce: String
  let receiptPath: String
  let processPath: String
  let phasePath: String
  let logPath: String
  let captureEnabled: Bool

  func writePhase(_ phase: String) {
    do {
      try Data("\(phase)\n".utf8).write(
        to: URL(fileURLWithPath: phasePath),
        options: .atomic
      )
    } catch {
      FileHandle.standardError.write(
        Data("error: could not record host phase \(phase): \(error)\n".utf8)
      )
    }
  }

  func finish(status: CInt) -> Never {
    writePhase("completed")
    do {
      try Data("\(nonce)\t\(getpid())\t\(status)\n".utf8).write(
        to: URL(fileURLWithPath: receiptPath),
        options: .atomic
      )
    } catch {
      FileHandle.standardError.write(
        Data("error: could not write test completion receipt: \(error)\n".utf8)
      )
      Darwin.exit(status == 0 ? 1 : status)
    }
    Darwin.exit(status)
  }

  static func read(at path: String) throws -> HostConfiguration {
    let fields = try Data(contentsOf: URL(fileURLWithPath: path))
      .split(separator: 0, omittingEmptySubsequences: false)
    guard (fields.count == 6 || fields.count == 7), fields.last?.isEmpty == true else {
      throw HostError("invalid AppKit test host configuration")
    }
    let values = try fields.dropLast().map { field -> String in
      guard let value = String(data: Data(field), encoding: .utf8) else {
        throw HostError("AppKit test host configuration is not UTF-8")
      }
      return value
    }
    guard (values.count == 5 || values.count == 6),
      UUID(uuidString: values[0]) != nil,
      values.prefix(5).allSatisfy({ !$0.isEmpty })
    else {
      throw HostError("invalid AppKit test host configuration values")
    }
    let captureEnabled: Bool
    if values.count == 6 {
      guard values[5] == "exit-observer-v1" else {
        throw HostError("invalid AppKit test host capture mode")
      }
      captureEnabled = true
    } else {
      captureEnabled = false
    }
    return HostConfiguration(
      nonce: values[0],
      receiptPath: values[1],
      processPath: values[2],
      phasePath: values[3],
      logPath: values[4],
      captureEnabled: captureEnabled
    )
  }
}

private struct HostError: Error, CustomStringConvertible {
  let description: String

  init(_ description: String) {
    self.description = description
  }
}

@MainActor
private final class AppKitTestApplicationDelegate: NSObject, NSApplicationDelegate {
  private let application: NSApplication
  private let testingArguments: Testing.__CommandLineArguments_v0
  private let configuration: HostConfiguration
  private var didStartTestRun = false

  init(
    application: NSApplication,
    testingArguments: Testing.__CommandLineArguments_v0,
    configuration: HostConfiguration
  ) {
    self.application = application
    self.testingArguments = testingArguments
    self.configuration = configuration
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard !didStartTestRun else {
      fail("AppKit test host received a duplicate applicationDidFinishLaunching callback")
    }
    didStartTestRun = true
    guard application.activationPolicy() == .regular else {
      fail("expected the LaunchServices test host to have regular activation policy")
    }
    configuration.writePhase("didFinishLaunching")

    writePhase("requestingActivation")
    application.activate(ignoringOtherApps: true)
    Task { @MainActor in
      guard await waitForActivation() else {
        fail("AppKit test host did not become active within 5 seconds")
      }
      await runTests()
    }
  }

  func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    finish(status: 1)
  }

  private func runTests() async {
    configuration.writePhase("runningTests")
    let status: CInt = await Testing.__swiftPMEntryPoint(passing: testingArguments)
    finish(status: status)
  }

  private func waitForActivation() async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(5))
    while true {
      if application.activationPolicy() == .regular && application.isActive {
        return true
      }
      let remaining = clock.now.duration(to: deadline)
      guard remaining > .zero else { return false }
      do {
        try await Task.sleep(for: min(.milliseconds(25), remaining))
      } catch {
        return false
      }
    }
  }

  private func writePhase(_ phase: String) {
    configuration.writePhase(phase)
  }

  private func finish(status: CInt) -> Never {
    configuration.finish(status: status)
  }
}
