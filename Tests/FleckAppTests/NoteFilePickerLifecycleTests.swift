#if os(macOS)
  import AppKit
  import Foundation
  import Testing

  @testable import FleckApp

  @Suite(.serialized)
  @MainActor
  struct NoteFilePickerLifecycleTests {
    @Test func admissionPrecedesSchedulingAndSuppressesDuplicateRequests() {
      var scheduled: [NoteFilePicker.Presenter.ScheduledWork] = []
      var firstResults: [NoteFilePicker.Result] = []
      var duplicateResults: [NoteFilePicker.Result] = []
      let url = URL(fileURLWithPath: "/tmp/accepted.txt")
      let presenter = NoteFilePicker.Presenter(
        schedule: { scheduled.append($0) },
        present: { .accepted(url) }
      )
      let picker = NoteFilePicker(presenter: presenter)

      #expect(picker.chooseFile { firstResults.append($0) })
      #expect(presenter.isPresenting)
      #expect(scheduled.count == 1)
      #expect(!picker.chooseFile { duplicateResults.append($0) })
      #expect(scheduled.count == 1)

      scheduled.removeFirst()()
      #expect(firstResults == [.accepted(url)])
      #expect(duplicateResults.isEmpty)
      #expect(!presenter.isPresenting)
    }

    @Test func acceptedCancelledAndAbortedResultsRemainDistinct() {
      let url = URL(fileURLWithPath: "/tmp/accepted.txt")

      #expect(
        NoteFilePicker.Result(response: .OK, url: url) == .accepted(url)
      )
      #expect(
        NoteFilePicker.Result(response: .cancel, url: url) == .cancelled
      )
      #expect(
        NoteFilePicker.Result(response: .abort, url: url) == .aborted
      )

      for expected in [
        NoteFilePicker.Result.accepted(url),
        .cancelled,
        .aborted,
      ] {
        var scheduled: [NoteFilePicker.Presenter.ScheduledWork] = []
        var delivered: NoteFilePicker.Result?
        let presenter = NoteFilePicker.Presenter(
          schedule: { scheduled.append($0) },
          present: { expected }
        )
        let picker = NoteFilePicker(presenter: presenter)
        #expect(picker.chooseFile { delivered = $0 })
        scheduled.removeFirst()()
        #expect(delivered == expected)
        #expect(!presenter.isPresenting)
      }
    }

    @Test func presenterResetsBeforeDeliveryAndCanOpenAgain() {
      var scheduled: [NoteFilePicker.Presenter.ScheduledWork] = []
      var presentations = 0
      var reopenedFromCompletion = false
      let presenter = NoteFilePicker.Presenter(
        schedule: { scheduled.append($0) },
        present: {
          presentations += 1
          return .cancelled
        }
      )
      let picker = NoteFilePicker(presenter: presenter)

      let admitted = picker.chooseFile { _ in
        #expect(!presenter.isPresenting)
        reopenedFromCompletion = picker.chooseFile { _ in }
      }
      #expect(admitted)
      scheduled.removeFirst()()

      #expect(reopenedFromCompletion)
      #expect(presenter.isPresenting)
      #expect(scheduled.count == 1)
      scheduled.removeFirst()()
      #expect(presentations == 2)
      #expect(!presenter.isPresenting)
    }
  }
#endif
