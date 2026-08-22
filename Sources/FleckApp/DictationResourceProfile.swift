import Darwin
import Foundation

enum DictationMemoryPressure: Equatable, Sendable {
  case normal
  case warning
  case critical
}

enum DictationThermalPressure: Equatable, Sendable {
  case nominal
  case fair
  case serious
  case critical

  static func current(
    thermalState: @escaping @Sendable () -> ProcessInfo.ThermalState = {
      ProcessInfo.processInfo.thermalState
    },
    mapThermalState: @escaping (ProcessInfo.ThermalState) -> Self? = { state in
      switch state {
      case .nominal:
        return .nominal
      case .fair:
        return .fair
      case .serious:
        return .serious
      case .critical:
        return .critical
      @unknown default:
        return .critical
      }
    }
  ) -> Self {
    mapThermalState(thermalState()) ?? .critical
  }
}

struct DictationResourceProfile: Equatable, Sendable {
  let installedMemoryBytes: UInt64
  let activeProcessorCount: Int

  init(installedMemoryBytes: UInt64, activeProcessorCount: Int) {
    self.installedMemoryBytes = installedMemoryBytes
    self.activeProcessorCount = activeProcessorCount
  }

  static func current(
    physicalMemory: @escaping @Sendable () -> UInt64 = {
      ProcessInfo.processInfo.physicalMemory
    },
    activeProcessorCount: @escaping @Sendable () -> Int = {
      ProcessInfo.processInfo.activeProcessorCount
    }
  ) -> Self {
    Self(
      installedMemoryBytes: physicalMemory(),
      activeProcessorCount: activeProcessorCount()
    )
  }
}

struct DictationResourceSnapshot: Equatable, Sendable {
  let reclaimableMemoryBytes: UInt64?
  let memoryPressure: DictationMemoryPressure
  let thermalPressure: DictationThermalPressure
  let lowPowerMode: Bool

  init(
    reclaimableMemoryBytes: UInt64?,
    memoryPressure: DictationMemoryPressure = .normal,
    thermalPressure: DictationThermalPressure = .nominal,
    lowPowerMode: Bool = false
  ) {
    self.reclaimableMemoryBytes = reclaimableMemoryBytes
    self.memoryPressure = memoryPressure
    self.thermalPressure = thermalPressure
    self.lowPowerMode = lowPowerMode
  }

  static func current(
    sampling: @escaping @Sendable () -> DictationResourceSampling? = {
      DictationResourceSampling.current()
    },
    memoryPressure: @escaping @Sendable () -> DictationMemoryPressure = {
      .normal
    },
    thermalPressure: @escaping @Sendable () -> DictationThermalPressure = {
      DictationThermalPressure.current()
    },
    lowPowerMode: @escaping @Sendable () -> Bool = {
      ProcessInfo.processInfo.isLowPowerModeEnabled
    }
  ) -> Self {
    Self(
      reclaimableMemoryBytes: sampling()?.reclaimableMemoryBytes,
      memoryPressure: memoryPressure(),
      thermalPressure: thermalPressure(),
      lowPowerMode: lowPowerMode()
    )
  }
}

struct DictationResourceSampling: Equatable, Sendable {
  struct HostAccess {
    let acquire: () -> mach_port_t
    let pageSize: (mach_port_t) -> UInt64?
    let pageCounts: (mach_port_t) -> PageCounts?
    let deallocate: (mach_port_t) -> Void

    init(
      acquire: @escaping () -> mach_port_t,
      pageSize: @escaping (mach_port_t) -> UInt64?,
      pageCounts: @escaping (mach_port_t) -> PageCounts?,
      deallocate: @escaping (mach_port_t) -> Void
    ) {
      self.acquire = acquire
      self.pageSize = pageSize
      self.pageCounts = pageCounts
      self.deallocate = deallocate
    }
  }

  struct PageCounts: Equatable, Sendable {
    let freePages: UInt64
    let inactivePages: UInt64
    let speculativePages: UInt64
    let purgeablePages: UInt64

    init(
      freePages: UInt64,
      inactivePages: UInt64,
      speculativePages: UInt64,
      purgeablePages: UInt64
    ) {
      self.freePages = freePages
      self.inactivePages = inactivePages
      self.speculativePages = speculativePages
      self.purgeablePages = purgeablePages
    }
  }

  let pageSize: UInt64
  let freePages: UInt64
  let inactivePages: UInt64
  let speculativePages: UInt64
  let purgeablePages: UInt64

  init(
    pageSize: UInt64,
    freePages: UInt64,
    inactivePages: UInt64,
    speculativePages: UInt64,
    purgeablePages: UInt64
  ) {
    self.pageSize = pageSize
    self.freePages = freePages
    self.inactivePages = inactivePages
    self.speculativePages = speculativePages
    self.purgeablePages = purgeablePages
  }

  var reclaimableMemoryBytes: UInt64? {
    guard pageSize > 0, speculativePages <= freePages else { return nil }

    var pageCount: UInt64 = 0
    // vm_statistics64 free_count already includes speculative_count.
    for pages in [freePages, inactivePages, purgeablePages] {
      let (nextPageCount, overflow) = pageCount.addingReportingOverflow(pages)
      guard !overflow else { return nil }
      pageCount = nextPageCount
    }

    let (bytes, overflow) = pageCount.multipliedReportingOverflow(by: pageSize)
    return overflow ? nil : bytes
  }

  static func sample(
    pageSize: @escaping @Sendable () -> UInt64?,
    pageCounts: @escaping @Sendable () -> PageCounts?
  ) -> Self? {
    guard let pageSize = pageSize(), let pageCounts = pageCounts() else {
      return nil
    }

    let sample = Self(
      pageSize: pageSize,
      freePages: pageCounts.freePages,
      inactivePages: pageCounts.inactivePages,
      speculativePages: pageCounts.speculativePages,
      purgeablePages: pageCounts.purgeablePages
    )
    return sample.reclaimableMemoryBytes == nil ? nil : sample
  }

  static func current() -> Self? {
    current(hostAccess: productionHostAccess())
  }

  static func current(hostAccess: HostAccess) -> Self? {
    let host = hostAccess.acquire()
    defer { hostAccess.deallocate(host) }

    guard let pageSize = hostAccess.pageSize(host),
          let pageCounts = hostAccess.pageCounts(host)
    else {
      return nil
    }

    return sample(
      pageSize: { pageSize },
      pageCounts: { pageCounts }
    )
  }

  private static func productionHostAccess() -> HostAccess {
    HostAccess(
      acquire: {
        mach_host_self()
      },
      pageSize: { host in
        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS else {
          return nil
        }
        return UInt64(pageSize)
      },
      pageCounts: { host in
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
          MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &statistics) {
          $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics64(
              host,
              HOST_VM_INFO64,
              $0,
              &count
            )
          }
        }
        guard result == KERN_SUCCESS else { return nil }

        return PageCounts(
          freePages: UInt64(statistics.free_count),
          inactivePages: UInt64(statistics.inactive_count),
          speculativePages: UInt64(statistics.speculative_count),
          purgeablePages: UInt64(statistics.purgeable_count)
        )
      },
      deallocate: { host in
        _ = mach_port_deallocate(mach_task_self_, host)
      }
    )
  }
}
