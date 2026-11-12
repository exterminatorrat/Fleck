import Foundation
import Testing

@testable import FleckApp

@Suite("SavedConfirmation")
@MainActor
struct SavedConfirmationTests {
  @Test func initialAndUnscheduledSuccessStayQuiet() {
    let scheduler = ConfirmationScheduler()
    let feedback = SaveFeedbackPresentation(scheduleConfirmation: scheduler.schedule)

    feedback.settle(.saved)

    #expect(!feedback.showsSavedConfirmation)
    #expect(scheduler.delays.isEmpty)
  }

  @Test func successfulChangesConfirmAfterIdleThenHide() {
    let scheduler = ConfirmationScheduler()
    let feedback = SaveFeedbackPresentation(scheduleConfirmation: scheduler.schedule)
    feedback.changesScheduled()
    let write = feedback.writeBegan()
    feedback.writeEnded(write)
    feedback.settle(.saved)

    #expect(!feedback.showsSavedConfirmation)
    #expect(scheduler.delays == [.milliseconds(1500)])
    scheduler.fire(0)
    #expect(feedback.showsSavedConfirmation)
    #expect(scheduler.delays == [.milliseconds(1500), .seconds(1)])
    scheduler.fire(1)
    #expect(!feedback.showsSavedConfirmation)
    #expect(feedback.state == .saved)
  }

  @Test func newActivityRestartsIdleAndIgnoresTheEarlierCallback() {
    let scheduler = ConfirmationScheduler()
    let feedback = SaveFeedbackPresentation(scheduleConfirmation: scheduler.schedule)
    feedback.changesScheduled()
    feedback.changesScheduled()
    let write = feedback.writeBegan()
    feedback.writeEnded(write)
    feedback.settle(.saved)

    scheduler.fire(0)
    #expect(!feedback.showsSavedConfirmation)
    scheduler.fire(1)
    #expect(feedback.showsSavedConfirmation)
  }

  @Test func idleDoesNotConfirmUncommittedOrNewerPendingChanges() {
    let scheduler = ConfirmationScheduler()
    let feedback = SaveFeedbackPresentation(scheduleConfirmation: scheduler.schedule)
    feedback.changesScheduled()

    scheduler.fire(0)
    #expect(!feedback.showsSavedConfirmation)
    feedback.settle(.pending)
    #expect(!feedback.showsSavedConfirmation)
    let write = feedback.writeBegan()
    #expect(!feedback.showsSavedConfirmation)
    feedback.writeEnded(write)
    feedback.settle(.saved)
    #expect(feedback.showsSavedConfirmation)
  }

  @Test func anotherSuccessCannotReplayTheConfirmation() {
    let scheduler = ConfirmationScheduler()
    let feedback = SaveFeedbackPresentation(scheduleConfirmation: scheduler.schedule)
    feedback.changesScheduled()
    let write = feedback.writeBegan()
    feedback.writeEnded(write)
    feedback.settle(.saved)
    scheduler.fire(0)
    feedback.settle(.saved)
    #expect(scheduler.delays.count == 2)

    scheduler.fire(1)
    feedback.settle(.saved)
    #expect(!feedback.showsSavedConfirmation)
    #expect(scheduler.delays.count == 2)
  }

  @Test func typingHidesConfirmationAndAnOldHideCannotAffectTheNextOne() {
    let scheduler = ConfirmationScheduler()
    let feedback = SaveFeedbackPresentation(scheduleConfirmation: scheduler.schedule)
    feedback.changesScheduled()
    let first = feedback.writeBegan()
    feedback.writeEnded(first)
    feedback.settle(.saved)
    scheduler.fire(0)
    #expect(feedback.showsSavedConfirmation)

    feedback.changesScheduled()
    #expect(!feedback.showsSavedConfirmation)
    let second = feedback.writeBegan()
    feedback.writeEnded(second)
    feedback.settle(.saved)
    scheduler.fire(2)
    #expect(feedback.showsSavedConfirmation)
    scheduler.fire(1)
    #expect(feedback.showsSavedConfirmation)
    scheduler.fire(3)
    #expect(!feedback.showsSavedConfirmation)
  }

  @Test func aFailedSaveDoesNotConfirmUntilASuccessfulRetry() {
    let scheduler = ConfirmationScheduler()
    let feedback = SaveFeedbackPresentation(scheduleConfirmation: scheduler.schedule)
    feedback.changesScheduled()
    let first = feedback.writeBegan()
    feedback.writeEnded(first)
    feedback.settle(.failed)
    scheduler.fire(0)
    #expect(feedback.state == .failed)
    #expect(!feedback.showsSavedConfirmation)

    feedback.changesScheduled()
    let retry = feedback.writeBegan()
    feedback.writeEnded(retry)
    feedback.settle(.saved)
    #expect(!feedback.showsSavedConfirmation)
    scheduler.fire(1)
    #expect(feedback.showsSavedConfirmation)
  }

  @Test func aSlowActualWriteTakesPriorityAndConfirmsOnlyWhenItEnds() {
    let reveal = ConfirmationScheduler()
    let confirmation = ConfirmationScheduler()
    let feedback = SaveFeedbackPresentation(
      scheduleReveal: reveal.schedule,
      scheduleConfirmation: confirmation.schedule
    )
    feedback.changesScheduled()
    let write = feedback.writeBegan()
    reveal.fire(0)
    confirmation.fire(0)
    #expect(feedback.state == .saving)
    #expect(!feedback.showsSavedConfirmation)
    feedback.writeEnded(write)
    feedback.settle(.saved)
    #expect(feedback.showsSavedConfirmation)

    let next = feedback.writeBegan()
    #expect(!feedback.showsSavedConfirmation)
    feedback.writeEnded(next)
    feedback.settle(.saved)
    #expect(!feedback.showsSavedConfirmation)
  }

  @Test func resetInvalidatesIdleAndHideCallbacks() {
    let scheduler = ConfirmationScheduler()
    let feedback = SaveFeedbackPresentation(scheduleConfirmation: scheduler.schedule)
    feedback.changesScheduled()
    feedback.reset()
    scheduler.fire(0)
    #expect(!feedback.showsSavedConfirmation)

    feedback.changesScheduled()
    let write = feedback.writeBegan()
    feedback.writeEnded(write)
    feedback.settle(.saved)
    scheduler.fire(1)
    #expect(feedback.showsSavedConfirmation)
    feedback.reset()
    scheduler.fire(2)
    #expect(!feedback.showsSavedConfirmation)
    #expect(feedback.state == .saved)
  }
}

@MainActor
private final class ConfirmationScheduler {
  private(set) var delays: [Duration] = []
  private var actions: [@MainActor () -> Void] = []

  func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) {
    delays.append(delay)
    actions.append(action)
  }

  func fire(_ index: Int) {
    guard actions.indices.contains(index) else {
      Issue.record("No confirmation callback was scheduled at index \(index)")
      return
    }
    actions[index]()
  }
}
