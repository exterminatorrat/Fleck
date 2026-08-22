import Darwin
import Foundation
import Testing

@testable import FleckApp

@Test func resourceSamplingUsesOneHostPortAndDeallocatesAfterSuccess() {
  let expectedHost: mach_port_t = 0xCAFE
  var events: [String] = []
  var pageSizeHost: mach_port_t?
  var statisticsHost: mach_port_t?
  var deallocatedHost: mach_port_t?

  let hostAccess = DictationResourceSampling.HostAccess(
    acquire: {
      events.append("acquire")
      return expectedHost
    },
    pageSize: { host in
      events.append("pageSize")
      pageSizeHost = host
      return 4_096
    },
    pageCounts: { host in
      events.append("statistics")
      statisticsHost = host
      return .init(
        freePages: 4,
        inactivePages: 2,
        speculativePages: 3,
        purgeablePages: 1
      )
    },
    deallocate: { host in
      events.append("deallocate")
      deallocatedHost = host
    }
  )

  let sample = DictationResourceSampling.current(hostAccess: hostAccess)

  #expect(sample?.reclaimableMemoryBytes == 7 * 4_096)
  #expect(pageSizeHost == expectedHost)
  #expect(statisticsHost == expectedHost)
  #expect(deallocatedHost == expectedHost)
  #expect(events == ["acquire", "pageSize", "statistics", "deallocate"])
}

@Test func resourceSamplingDeallocatesAfterPageSizeFailure() {
  let expectedHost: mach_port_t = 0xCAFE
  var events: [String] = []

  let hostAccess = DictationResourceSampling.HostAccess(
    acquire: {
      events.append("acquire")
      return expectedHost
    },
    pageSize: { host in
      events.append("pageSize:\(host)")
      return nil
    },
    pageCounts: { _ in
      events.append("statistics")
      return nil
    },
    deallocate: { host in
      events.append("deallocate:\(host)")
    }
  )

  #expect(DictationResourceSampling.current(hostAccess: hostAccess) == nil)
  #expect(events == ["acquire", "pageSize:\(expectedHost)", "deallocate:\(expectedHost)"])
}

@Test func resourceSamplingDeallocatesAfterStatisticsFailure() {
  let expectedHost: mach_port_t = 0xCAFE
  var events: [String] = []

  let hostAccess = DictationResourceSampling.HostAccess(
    acquire: {
      events.append("acquire")
      return expectedHost
    },
    pageSize: { host in
      events.append("pageSize:\(host)")
      return 4_096
    },
    pageCounts: { host in
      events.append("statistics:\(host)")
      return nil
    },
    deallocate: { host in
      events.append("deallocate:\(host)")
    }
  )

  #expect(DictationResourceSampling.current(hostAccess: hostAccess) == nil)
  #expect(events == [
    "acquire",
    "pageSize:\(expectedHost)",
    "statistics:\(expectedHost)",
    "deallocate:\(expectedHost)",
  ])
}

@Test func unrecognizedThermalMappingFailsClosedToZeroRetention() {
  let thermalPressure = DictationThermalPressure.current(
    thermalState: { .nominal },
    mapThermalState: { _ in nil }
  )
  let profile = DictationResourceProfile(
    installedMemoryBytes: 24 * gib,
    activeProcessorCount: 10
  )
  let snapshot = DictationResourceSnapshot(
    reclaimableMemoryBytes: 16 * gib,
    thermalPressure: thermalPressure
  )

  #expect(thermalPressure == .critical)
  #expect(
    DictationRuntimePolicy.policy(memoryBytes: profile.installedMemoryBytes)
      .parakeetRetention(profile: profile, snapshot: snapshot) == .zero
  )
}

@Test func resourceProfileUsesInjectedProductionProviders() {
  let profile = DictationResourceProfile.current(
    physicalMemory: { 24 * gib },
    activeProcessorCount: { 10 }
  )

  #expect(profile == DictationResourceProfile(
    installedMemoryBytes: 24 * gib,
    activeProcessorCount: 10
  ))
}

@Test func resourceSnapshotUsesInjectedSamplingProviders() {
  let sample = DictationResourceSampling(
    pageSize: 4_096,
    freePages: 4,
    inactivePages: 2,
    speculativePages: 3,
    purgeablePages: 1
  )
  let snapshot = DictationResourceSnapshot.current(
    sampling: { sample },
    memoryPressure: { .warning },
    thermalPressure: { .serious },
    lowPowerMode: { true }
  )

  #expect(snapshot == DictationResourceSnapshot(
    reclaimableMemoryBytes: 7 * 4_096,
    memoryPressure: .warning,
    thermalPressure: .serious,
    lowPowerMode: true
  ))
}

@Test func resourceSamplingUsesRawFreeCountWithoutDoubleCountingSpeculativePages() {
  let sample = DictationResourceSampling(
    pageSize: 4_096,
    freePages: 4,
    inactivePages: 2,
    speculativePages: 3,
    purgeablePages: 1
  )

  #expect(sample.reclaimableMemoryBytes == 7 * 4_096)
}

@Test func resourceSamplingRejectsSpeculativePagesAboveRawFreeCount() {
  let counts = DictationResourceSampling.PageCounts(
    freePages: 2,
    inactivePages: 0,
    speculativePages: 3,
    purgeablePages: 0
  )
  let sample = DictationResourceSampling(
    pageSize: 4_096,
    freePages: counts.freePages,
    inactivePages: counts.inactivePages,
    speculativePages: counts.speculativePages,
    purgeablePages: counts.purgeablePages
  )

  #expect(sample.reclaimableMemoryBytes == nil)
  #expect(DictationResourceSampling.sample(
    pageSize: { 4_096 },
    pageCounts: { counts }
  ) == nil)
}

@Test func resourceSamplingFailsOnProviderFailureAndOverflow() {
  let counts = DictationResourceSampling.PageCounts(
    freePages: 3,
    inactivePages: 2,
    speculativePages: 3,
    purgeablePages: 4
  )

  #expect(DictationResourceSampling.sample(
    pageSize: { nil },
    pageCounts: { counts }
  ) == nil)
  #expect(DictationResourceSampling.sample(
    pageSize: { 4_096 },
    pageCounts: { nil }
  ) == nil)

  let overflowingPageCount = DictationResourceSampling(
    pageSize: UInt64.max,
    freePages: 2,
    inactivePages: 0,
    speculativePages: 0,
    purgeablePages: 0
  )
  #expect(overflowingPageCount.reclaimableMemoryBytes == nil)

  let overflowingPageCounts = DictationResourceSampling.PageCounts(
    freePages: UInt64.max,
    inactivePages: 1,
    speculativePages: 0,
    purgeablePages: 0
  )
  let overflowingPageSum = DictationResourceSampling(
    pageSize: 1,
    freePages: overflowingPageCounts.freePages,
    inactivePages: overflowingPageCounts.inactivePages,
    speculativePages: overflowingPageCounts.speculativePages,
    purgeablePages: overflowingPageCounts.purgeablePages
  )
  #expect(overflowingPageSum.reclaimableMemoryBytes == nil)
  #expect(DictationResourceSampling.sample(
    pageSize: { 1 },
    pageCounts: { overflowingPageCounts }
  ) == nil)
}

private let gib: UInt64 = 1_024 * 1_024 * 1_024
