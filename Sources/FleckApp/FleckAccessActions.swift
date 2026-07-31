import Foundation

enum FleckAccessState: Equatable, Sendable {
  case loading
  case trialNotStarted
  case trialActive(expiresAt: Date)
  case purchased
  case unavailable

  var hasFullAccess: Bool {
    switch self {
    case .trialActive, .purchased:
      true
    case .loading, .trialNotStarted, .unavailable:
      false
    }
  }
}

enum FleckAccessAction: Equatable, Sendable {
  case startTrial
  case purchaseLifetime
  case restorePurchase
}

enum FleckAccessActionResult: Equatable, Sendable {
  case trialActive(expiresAt: Date)
  case purchased
  case cancelled
  case pending
  case nothingToRestore
  case unavailable
  case failed(String)
}

struct FleckAccessPresentation: Equatable, Sendable {
  var state: FleckAccessState
  var localizedLifetimePrice: String?
  var inFlightAction: FleckAccessAction?
  var message: String?

  var hasFullAccess: Bool { state.hasFullAccess }
}

@MainActor
protocol FleckAccessActions: AnyObject {
  var presentation: FleckAccessPresentation { get }
  func refresh() async
  func startTrial() async -> FleckAccessActionResult
  func purchaseLifetime() async -> FleckAccessActionResult
  func restorePurchase() async -> FleckAccessActionResult
}

@MainActor
final class UnavailableFleckAccessActions: FleckAccessActions {
  private(set) var presentation = FleckAccessPresentation(
    state: .unavailable,
    localizedLifetimePrice: nil,
    inFlightAction: nil,
    message: "Access setup is unavailable in this development build."
  )

  func refresh() async {}
  func startTrial() async -> FleckAccessActionResult { .unavailable }
  func purchaseLifetime() async -> FleckAccessActionResult { .unavailable }
  func restorePurchase() async -> FleckAccessActionResult { .unavailable }
}
