#if os(macOS)
  import AppKit
  import FleckCore
  import SwiftUI

  private struct ModelsAccessibilityProbe: NSViewRepresentable {
    let identifier: String

    func makeNSView(context: Context) -> NSView {
      let view = NSView()
      view.setAccessibilityElement(false)
      view.setAccessibilityIdentifier(identifier)
      return view
    }

    func updateNSView(_ view: NSView, context: Context) {
      view.setAccessibilityIdentifier(identifier)
    }
  }

  private struct ModelsMonitoredEvent: @unchecked Sendable {
    let event: NSEvent
  }

  @MainActor
  private struct ModelsSearchFocusResigner: NSViewRepresentable {
    let isFocused: Bool
    let hasDetails: Bool
    let isModalPresented: Bool
    let onFocusLoss: () -> Void
    let onCloseDetails: () -> Void

    func makeCoordinator() -> Coordinator {
      Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
      let view = NSView()
      view.setAccessibilityElement(false)
      return view
    }

    func updateNSView(_ view: NSView, context: Context) {
      context.coordinator.update(
        view,
        isFocused: isFocused,
        hasDetails: hasDetails,
        isModalPresented: isModalPresented,
        onFocusLoss: onFocusLoss,
        onCloseDetails: onCloseDetails
      )
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
      coordinator.stopMonitoring()
    }

    @MainActor
    final class Coordinator {
      private weak var window: NSWindow?
      private var eventMonitor: Any?
      private var isFocused = false
      private var hasDetails = false
      private var isModalPresented = false
      private var onFocusLoss: () -> Void = {}
      private var onCloseDetails: () -> Void = {}

      func update(
        _ view: NSView,
        isFocused: Bool,
        hasDetails: Bool,
        isModalPresented: Bool,
        onFocusLoss: @escaping () -> Void,
        onCloseDetails: @escaping () -> Void
      ) {
        self.onFocusLoss = onFocusLoss
        self.onCloseDetails = onCloseDetails

        if window !== view.window {
          stopMonitoring()
          window = view.window
        }

        let didLoseFocus = self.isFocused && !isFocused
        self.isFocused = isFocused
        self.hasDetails = hasDetails
        self.isModalPresented = isModalPresented
        if didLoseFocus {
          resignSearchField(in: view.window)
        }

        guard isFocused || (hasDetails && !isModalPresented), window != nil else {
          stopMonitoring()
          return
        }

        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(
          matching: [.leftMouseDown, .keyDown]
        ) { [weak self] event in
          guard let self else { return event }
          let monitoredEvent = ModelsMonitoredEvent(event: event)
          let shouldConsume = MainActor.assumeIsolated { self.handle(monitoredEvent.event) }
          return shouldConsume ? nil : event
        }
      }

      func stopMonitoring() {
        if let eventMonitor {
          NSEvent.removeMonitor(eventMonitor)
          self.eventMonitor = nil
        }
      }

      private func handle(_ event: NSEvent) -> Bool {
        guard let window, event.window === window else { return false }

        if event.type == .keyDown, event.keyCode == 53, !isModalPresented {
          if let editor = window.firstResponder as? NSTextView, editor.isFieldEditor {
            guard let field = activeTextField(in: window),
              field.placeholderString == "Search models"
            else {
              return false
            }
            onFocusLoss()
            isFocused = false
            resignSearchField(in: window)
            if !hasDetails { stopMonitoring() }
            return true
          }
          if hasDetails {
            onCloseDetails()
            hasDetails = false
            stopMonitoring()
            return true
          }
          return false
        }

        guard event.type == .leftMouseDown,
          let field = activeTextField(in: window),
          field.placeholderString == "Search models",
          !field.convert(field.bounds, to: nil).contains(event.locationInWindow)
        else {
          return false
        }

        onFocusLoss()
        isFocused = false
        if !hasDetails { stopMonitoring() }
        Task { @MainActor [weak self, weak window] in
          await Task.yield()
          guard let self, let window,
            self.activeTextField(in: window) === field
          else {
            return
          }
          self.resignSearchField(in: window)
        }
        return false
      }

      private func resignSearchField(in window: NSWindow?) {
        guard let window,
          let field = activeTextField(in: window),
          field.placeholderString == "Search models"
        else {
          return
        }
        window.makeFirstResponder(nil)
      }

      private func activeTextField(in window: NSWindow) -> NSTextField? {
        guard let editor = window.firstResponder as? NSTextView,
          editor.isFieldEditor,
          let field = editor.delegate as? NSTextField,
          field.currentEditor() === editor
        else {
          return nil
        }
        return field
      }
    }
  }

  @MainActor
  struct ModelsBrowserView: View {
    @Environment(\.fleckThemeSnapshot) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var speechViewModel: AdmittedModelSettingsViewModel
    @ObservedObject private var cleanupViewModel: AdmittedModelSettingsViewModel
    @Binding private var pinnedModelKeys: Set<String>
    @SceneStorage("models.search") private var storedSearchQuery = ""
    @SceneStorage("models.provider") private var providerFilter = "all"
    @SceneStorage("models.type") private var modelTypeFilter = ModelLibraryTypeFilter.all.rawValue
    @SceneStorage("models.sort.ascending") private var storedSortAscending = true
    @State private var sortAscending = true
    @SceneStorage("models.selectedID") private var sceneSelectedModelID: String?
    private let selectedModelIDOverride: Binding<String?>?
    @SceneStorage("models.visibleID") private var visibleModelID: String?
    @FocusState private var focusedModelID: String?
    @FocusState private var searchIsFocused: Bool
    @State private var hoveredModelID: String?
    @State private var pendingRemoval: ModelLibraryEntry?
    @State private var pendingInstallReview: PendingModelInstallReview?
    @State private var attributionIsExpanded = false
    private let searchQueryOverride: Binding<String>?
    private let typeFilterOverride: Binding<ModelLibraryTypeFilter>?

    init(
      speechViewModel: AdmittedModelSettingsViewModel,
      cleanupViewModel: AdmittedModelSettingsViewModel,
      pinnedModelKeys: Binding<Set<String>>,
      selectedModelID: Binding<String?>? = nil,
      searchQuery: Binding<String>? = nil,
      typeFilter: Binding<ModelLibraryTypeFilter>? = nil
    ) {
      _speechViewModel = ObservedObject(wrappedValue: speechViewModel)
      _cleanupViewModel = ObservedObject(wrappedValue: cleanupViewModel)
      _pinnedModelKeys = pinnedModelKeys
      selectedModelIDOverride = selectedModelID
      searchQueryOverride = searchQuery
      typeFilterOverride = typeFilter
    }

    private var searchQuery: String {
      get { searchQueryOverride?.wrappedValue ?? storedSearchQuery }
      nonmutating set {
        if let searchQueryOverride {
          searchQueryOverride.wrappedValue = newValue
        } else {
          storedSearchQuery = newValue
        }
      }
    }

    private var searchQueryBinding: Binding<String> {
      searchQueryOverride ?? $storedSearchQuery
    }

    private var modelTypeFilterBinding: Binding<ModelLibraryTypeFilter> {
      Binding(
        get: {
          typeFilterOverride?.wrappedValue
            ?? ModelLibraryTypeFilter(rawValue: modelTypeFilter)
            ?? .all
        },
        set: { value in
          if let typeFilterOverride {
            typeFilterOverride.wrappedValue = value
          } else {
            modelTypeFilter = value.rawValue
          }
        }
      )
    }

    private var entries: [ModelLibraryEntry] {
      ModelLibraryCatalog.entries(
        speechViewModel: speechViewModel,
        cleanupViewModel: cleanupViewModel
      )
    }

    private var visibleEntries: [ModelLibraryEntry] {
      ModelLibraryCatalog.filtered(
        entries,
        searchQuery: searchQuery,
        provider: providerFilter,
        type: modelTypeFilterBinding.wrappedValue,
        pins: pinnedModelKeys,
        ascending: sortAscending
      )
    }

    private var providerOptions: [ModelLibraryProvider] {
      ModelLibraryCatalog.providers(in: entries)
    }

    private var selectedEntry: ModelLibraryEntry? {
      guard let selectedModelID else { return nil }
      return visibleEntries.first { $0.id == selectedModelID }
    }

    private var selectedModelID: String? {
      if let selectedModelIDOverride {
        return selectedModelIDOverride.wrappedValue
      }
      return sceneSelectedModelID
    }

    private func setSelectedModelID(_ modelID: String?) {
      if let selectedModelIDOverride {
        selectedModelIDOverride.wrappedValue = modelID
      } else {
        sceneSelectedModelID = modelID
      }
    }

    private var unavailableDetails: [String] {
      [speechViewModel.presentation, cleanupViewModel.presentation]
        .filter { $0.descriptor == nil && $0.showsDetail }
        .map(\.detail)
    }

    private var removalDialogIsPresented: Binding<Bool> {
      Binding(
        get: { pendingRemoval != nil },
        set: { if !$0 { pendingRemoval = nil } }
      )
    }

    private var removalDialogTitle: String {
      pendingRemoval.map { "Remove \($0.title)?" } ?? "Remove model?"
    }

    var body: some View {
      GeometryReader { geometry in
        VStack(alignment: .leading, spacing: geometry.size.width < 680 ? 10 : 16) {
          header
          filters
          GeometryReader { contentGeometry in
            content(width: contentGeometry.size.width)
          }
          .frame(minHeight: 0)
        }
        .padding(geometry.size.width < 680 ? 12 : 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
      .background(theme.color(.window))
      .background(ModelsAccessibilityProbe(identifier: "models-browser"))
      .accessibilityIdentifier("models-browser")
      .onChange(of: entries.map(\.id)) { _, availableIDs in
        guard let selectedModelID, !availableIDs.contains(selectedModelID) else { return }
        setSelectedModelID(nil)
        focusedModelID = nil
      }
      .onChange(of: visibleEntries.map(\.id)) { _, matchingIDs in
        guard let selectedModelID, !matchingIDs.contains(selectedModelID) else { return }
        setSelectedModelID(nil)
      }
      .onAppear {
        sortAscending = storedSortAscending
      }
      .onChange(of: sortAscending) { _, value in
        storedSortAscending = value
      }
      .task {
        await speechViewModel.refresh()
        await cleanupViewModel.refresh()
      }
      .confirmationDialog(
        removalDialogTitle,
        isPresented: removalDialogIsPresented,
        titleVisibility: .visible
      ) {
        if let pendingRemoval {
          Button("Remove Model", role: .destructive) {
            pendingRemoval.viewModel.perform(.remove)
            self.pendingRemoval = nil
          }
          .accessibilityIdentifier("models-confirm-removal")
        }
        Button("Cancel", role: .cancel) { pendingRemoval = nil }
      } message: {
        if let pendingRemoval {
          Text(
            "Fleck will remove this model from this Mac and return to \(pendingRemoval.fallbackName). Pinning and viewing a model never change which engine is used."
          )
        }
      }
      .sheet(item: $pendingInstallReview) { review in
        ModelInstallReviewSheet(
          entry: review.entry,
          action: review.action,
          requiresTermsAcceptance: review.requiresTermsAcceptance
        ) {
          review.entry.viewModel.perform(review.action)
        }
      }
    }

    private var header: some View {
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .center, spacing: 24) {
          headerTitle
            .frame(maxWidth: .infinity, alignment: .leading)
          searchField
            .frame(width: 370)
        }
        VStack(alignment: .leading, spacing: 12) {
          headerTitle
          searchField
        }
      }
    }

    private var headerTitle: some View {
      VStack(alignment: .leading, spacing: 4) {
        Text("Models")
          .font(.title2.weight(.semibold))
        Text(
          "Optional models run locally on this Mac. Fleck returns to its built-in local paths whenever a model is not installed and healthy."
        )
        .font(.callout)
        .foregroundStyle(theme.color(.textSecondary))
        .fixedSize(horizontal: false, vertical: true)
      }
    }

    private var searchField: some View {
      let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
      return HStack(spacing: 8) {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(theme.color(.textSecondary))
          .accessibilityHidden(true)

        TextField("Search models", text: searchQueryBinding)
          .textFieldStyle(.plain)
          .focused($searchIsFocused)
          .accessibilityLabel("Search models")
          .accessibilityValue(searchQuery.isEmpty ? "No search" : searchQuery)
          .accessibilityHint("Filters the available optional models.")
          .accessibilityIdentifier("models-search-field")
      }
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 10)
      .frame(minHeight: 34, maxHeight: 34)
      .background(theme.color(.card), in: shape)
      .overlay {
        shape.strokeBorder(
          theme.color(.border).opacity(theme.increasedContrast ? 0.85 : 0.4),
          lineWidth: 1
        )
      }
      .fleckNeutralControlOutline(isFocused: searchIsFocused, cornerRadius: 7)
      .accessibilityElement(children: .contain)
      .background(
        ModelsSearchFocusResigner(
          isFocused: searchIsFocused,
          hasDetails: selectedModelID != nil,
          isModalPresented: pendingRemoval != nil || pendingInstallReview != nil,
          onFocusLoss: { searchIsFocused = false },
          onCloseDetails: closeDetails
        )
      )
    }

    private var filters: some View {
      HStack(spacing: 12) {
        Picker("Provider", selection: $providerFilter) {
          Text("All providers").tag("all")
          ForEach(providerOptions) { provider in
            Text(provider.rawValue).tag(provider.rawValue)
          }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("models-provider-filter")

        Picker(
          "Model type",
          selection: modelTypeFilterBinding
        ) {
          ForEach(ModelLibraryTypeFilter.allCases) { type in
            Text(type.rawValue).tag(type)
          }
        }
        .pickerStyle(.segmented)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityIdentifier("models-type-filter")

        Spacer(minLength: 0)
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("models-filters")
    }

    @ViewBuilder
    private func content(width: CGFloat) -> some View {
      if entries.isEmpty {
        emptyState
      } else if unavailableDetails.isEmpty {
        admittedContent(width: width)
      } else {
        VStack(alignment: .leading, spacing: 12) {
          unavailableDetailsView(centered: false)
          admittedContent(width: width)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
    }

    @ViewBuilder
    private func admittedContent(width: CGFloat) -> some View {
      if visibleEntries.isEmpty {
        noMatchesState
      } else if let selectedEntry {
        if ModelLibraryLayout.stacksDetails(width: width, dynamicTypeSize: dynamicTypeSize) {
          detailView(selectedEntry)
        } else {
          HStack(alignment: .top, spacing: 20) {
            compactList(visibleEntries)
              .frame(width: 292)
            Rectangle()
              .fill(theme.color(.border))
              .frame(width: 1)
            detailView(selectedEntry)
              .frame(maxWidth: .infinity)
          }
        }
      } else if ModelLibraryLayout.stacksDetails(width: width, dynamicTypeSize: dynamicTypeSize) {
        compactList(visibleEntries)
      } else {
        fullTable(visibleEntries)
      }
    }

    private var emptyState: some View {
      ScrollView {
        VStack(spacing: 12) {
          Image(systemName: "waveform")
            .font(.system(size: 28))
            .foregroundStyle(theme.color(.textSecondary))
            .accessibilityHidden(true)
          Text(
            "No optional local models are available in this build. Dictation still uses its built-in local paths."
          )
          .font(.headline)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("models-empty-state")
          if !unavailableDetails.isEmpty {
            unavailableDetailsView(centered: true)
          }
        }
        .frame(maxWidth: 560)
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: 260)
      }
    }

    private func unavailableDetailsView(centered: Bool) -> some View {
      VStack(alignment: centered ? .center : .leading, spacing: 6) {
        ForEach(Array(unavailableDetails.enumerated()), id: \.offset) { index, detail in
          Text(detail)
            .font(.callout)
            .foregroundStyle(theme.color(.textSecondary))
            .multilineTextAlignment(centered ? .center : .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("models-unavailable-role-detail-\(index)")
        }
      }
      .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
      .accessibilityElement(children: .contain)
    }

    private var noMatchesState: some View {
      VStack(spacing: 10) {
        Text("No models match these filters.")
          .font(.headline)
        Button("Clear filters", action: clearFilters)
          .accessibilityIdentifier("models-clear-filters")
      }
      .frame(maxWidth: .infinity, minHeight: 260)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("models-empty-filter-results")
    }

    private func fullTable(_ entries: [ModelLibraryEntry]) -> some View {
      VStack(spacing: 0) {
        HStack(spacing: 12) {
          Color.clear.frame(width: 28, height: 1)
          sortByNameButton(title: "Model name")
            .frame(maxWidth: .infinity, alignment: .leading)

          Text("Type")
            .frame(width: 88, alignment: .leading)
          Text("External results")
            .frame(width: 230, alignment: .leading)
          Text("Size")
            .frame(width: 78, alignment: .trailing)
          Text("Action")
            .frame(width: 94, alignment: .center)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(theme.color(.textSecondary))
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("models-table-header")

        Rectangle()
          .fill(theme.color(.border))
          .frame(height: 1)

        modelList(entries, compact: false)
      }
    }

    private func compactList(_ entries: [ModelLibraryEntry]) -> some View {
      VStack(spacing: 0) {
        HStack {
          sortByNameButton(title: "Sort by model name")
          Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("models-compact-sort-header")
        .font(.caption.weight(.medium))
        .foregroundStyle(theme.color(.textSecondary))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)

        Rectangle()
          .fill(theme.color(.border))
          .frame(height: 1)

        modelList(entries, compact: true)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func modelList(_ entries: [ModelLibraryEntry], compact: Bool) -> some View {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 4) {
            ForEach(entries) { entry in
              Group {
                if compact {
                  compactRow(entry)
                } else {
                  tableRow(entry)
                }
              }
              .id(entry.id)
            }
          }
          .scrollTargetLayout()
          .padding(.vertical, 6)
        }
        .scrollPosition(id: $visibleModelID, anchor: .top)
        .onMoveCommand { direction in
          moveRowFocus(direction, in: entries, proxy: proxy)
        }
        .accessibilityIdentifier(compact ? "models-compact-list" : "models-table")
      }
    }

    private func tableRow(_ entry: ModelLibraryEntry) -> some View {
      HStack(spacing: 12) {
        pinButton(entry)
          .frame(width: 28)
        Button {
          openDetails(entry)
        } label: {
          HStack(spacing: 12) {
            HStack(spacing: 9) {
              Image(systemName: entry.symbol)
                .font(.title3)
                .foregroundStyle(theme.color(.textSecondary))
                .accessibilityHidden(true)
              VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                  .font(.body.weight(.medium))
                  .lineLimit(1)
                Text(
                  "\(entry.provider.rawValue) · \(entry.languageNames.joined(separator: ", ")) · \(entry.presentation.compactStatus)"
                )
                  .font(.caption)
                  .foregroundStyle(theme.color(.textSecondary))
                  .lineLimit(1)
                if let progress = entry.presentation.progress {
                  ProgressView(value: progress)
                    .frame(maxWidth: 120)
                    .accessibilityLabel("\(entry.title) installation progress")
                    .accessibilityValue(
                      "\(entry.presentation.compactStatus), \(entry.presentation.progressAccessibilityValue ?? "")"
                    )
                } else if entry.presentation.showsDetail {
                  Text(entry.presentation.detail)
                    .font(.caption)
                    .foregroundStyle(detailColor(entry.presentation.phase))
                    .lineLimit(1)
                }
              }
              Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)

            Text(entry.shortTypeTitle)
              .font(.callout)
              .frame(width: 88, alignment: .leading)

            externalMetricSummary(entry)
              .frame(width: 230, alignment: .leading)

            Text(ModelLibraryFormatting.megabytes(entry.descriptor.downloadBytes))
              .font(.callout)
              .monospacedDigit()
              .frame(width: 78, alignment: .trailing)
              .accessibilityLabel(
                "Download size, \(ModelLibraryFormatting.megabytes(entry.descriptor.downloadBytes))"
              )
          }
          .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focusedModelID, equals: entry.id)
        .accessibilityLabel(entry.title)
        .accessibilityValue(rowAccessibilityValue(entry))
        .accessibilityHint("Opens model details. This does not change which model Fleck uses.")
        .accessibilityIdentifier("models-row-\(entry.id)")

        actionButton(entry, prominent: false)
          .frame(width: 94)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background(rowBackground(entry))
      .overlay(rowFocusRing(entry))
      .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
      .onHover { updateHover(entry.id, inside: $0) }
      .accessibilityElement(children: .contain)
    }

    private func compactRow(_ entry: ModelLibraryEntry) -> some View {
      HStack(alignment: .top, spacing: 7) {
        pinButton(entry)
          .frame(width: 28)
        Button {
          openDetails(entry)
        } label: {
          VStack(alignment: .leading, spacing: 3) {
            Text(entry.title)
              .font(.callout.weight(.medium))
              .lineLimit(1)
            HStack(spacing: 6) {
              Text(entry.provider.rawValue)
              Text("·")
              Text(entry.presentation.compactStatus)
            }
            .font(.caption)
            .foregroundStyle(theme.color(.textSecondary))
            .lineLimit(1)
            externalMetricSummary(entry)
          }
          .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focusedModelID, equals: entry.id)
        .accessibilityLabel(entry.title)
        .accessibilityValue(rowAccessibilityValue(entry))
        .accessibilityHint("Opens model details. This does not change which model Fleck uses.")
        .accessibilityIdentifier("models-row-\(entry.id)")
        if selectedModelID != entry.id {
          actionButton(entry, prominent: false)
            .frame(width: 86)
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(rowBackground(entry))
      .overlay(rowFocusRing(entry))
      .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
      .onHover { updateHover(entry.id, inside: $0) }
      .accessibilityElement(children: .contain)
    }

    private func externalMetricSummary(_ entry: ModelLibraryEntry) -> some View {
      let evidence = externalEvidence(for: entry)
      return VStack(alignment: .leading, spacing: 4) {
        ForEach(evidence?.metrics ?? []) { metric in
          Text("\(metric.label): \(compactExternalMetricValue(metric.value))")
            .font(.caption.weight(.medium))
            .fixedSize(horizontal: false, vertical: true)
        }
        if let evidence {
          Text(externalHardwareQualifier(for: evidence).map { "External · \($0)" } ?? "External")
            .font(.caption2)
            .foregroundStyle(theme.color(.textSecondary))
          if evidence.unmeasuredCleanupAccuracyContext != nil {
            Text("Cleanup accuracy: Not measured")
              .font(.caption2)
              .foregroundStyle(theme.color(.textSecondary))
          }
        } else {
          Text("No external results supplied")
            .font(.caption2)
            .foregroundStyle(theme.color(.textSecondary))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("models-external-metrics-\(entry.id)")
    }

    private func pinButton(_ entry: ModelLibraryEntry) -> some View {
      let isPinned = pinnedModelKeys.contains(entry.id)
      return Button {
        if isPinned {
          pinnedModelKeys.remove(entry.id)
        } else {
          pinnedModelKeys.insert(entry.id)
        }
      } label: {
        Image(systemName: isPinned ? "star.fill" : "star")
          .font(.body)
          .foregroundStyle(isPinned ? theme.color(.accent) : theme.color(.textSecondary))
          .frame(width: 24, height: 28)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(isPinned ? "Unpin \(entry.title)" : "Pin \(entry.title)")
      .accessibilityValue(isPinned ? "Pinned" : "Not pinned")
      .accessibilityHint("Pinning only moves this model to the top of the list.")
      .accessibilityIdentifier("models-pin-\(entry.id)")
    }

    @ViewBuilder
    private func actionButton(_ entry: ModelLibraryEntry, prominent: Bool) -> some View {
      if let action = entry.presentation.primaryAction {
        let label = actionTitle(
          action,
          presentation: entry.presentation,
          installLabel: prominent ? "Install" : "Download"
        )
        if prominent {
          Button(role: action == .remove ? .destructive : nil) {
            perform(action, for: entry)
          } label: {
            Text(label)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.regular)
          .accessibilityHint(actionHint(action, model: entry))
          .accessibilityIdentifier("models-action-\(entry.id)")
        } else {
          Button(role: action == .remove ? .destructive : nil) {
            perform(action, for: entry)
          } label: {
            Text(label)
              .lineLimit(1)
              .minimumScaleFactor(0.85)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .accessibilityHint(actionHint(action, model: entry))
          .accessibilityIdentifier("models-action-\(entry.id)")
        }
      }
    }

    private func detailView(_ entry: ModelLibraryEntry) -> some View {
      VStack(alignment: .leading, spacing: 0) {
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            Button(action: closeDetails) {
              Label("Back to models", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("models-back")

            HStack(alignment: .top, spacing: 12) {
              VStack(alignment: .leading, spacing: 5) {
                Text(entry.title)
                  .font(.title2.weight(.semibold))
                  .accessibilityIdentifier("models-detail-title")
                Text("\(entry.provider.rawValue) · \(entry.typeTitle)")
                  .font(.callout)
                  .foregroundStyle(theme.color(.textSecondary))
              }
              Spacer(minLength: 4)
              pinButton(entry)
            }

            Text(entry.purpose)
              .font(.body)
              .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .center, spacing: 10) {
              statusBadge(entry.presentation)
              Text("Fleck uses this automatically while installed and healthy.")
                .font(.callout)
                .foregroundStyle(theme.color(.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
            }

            detailSpecifications(entry)
            attributionSection(entry)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.bottom, 12)
        }

        Rectangle()
          .fill(theme.color(.border))
          .frame(height: 1)
          .padding(.vertical, 12)

        HStack(alignment: .center, spacing: 16) {
          VStack(alignment: .leading, spacing: 4) {
            if entry.presentation.showsDetail {
              Text(entry.presentation.detail)
                .font(.callout)
                .foregroundStyle(detailColor(entry.presentation.phase))
                .fixedSize(horizontal: false, vertical: true)
            } else {
              Text("Installed models are used automatically when healthy.")
                .font(.callout)
                .foregroundStyle(theme.color(.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
            }
            if let progress = entry.presentation.progress {
              ProgressView(value: progress)
                .accessibilityLabel("\(entry.title) installation progress")
                .accessibilityValue(
                  "\(entry.presentation.compactStatus), \(entry.presentation.progressAccessibilityValue ?? "")"
                )
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          actionButton(entry, prominent: true)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("models-detail-\(entry.id)")
    }

    private func detailSpecifications(_ entry: ModelLibraryEntry) -> some View {
      VStack(alignment: .leading, spacing: 12) {
        Text("Verified capabilities")
          .font(.headline)
        LabeledContent("Type", value: entry.typeTitle)
        LabeledContent("Execution", value: "Local, on this Mac")
        LabeledContent("Languages", value: entry.languageNames.joined(separator: ", "))
        LabeledContent(
          "Architecture",
          value: entry.descriptor.architectures.joined(separator: ", ")
        )

        Divider()

        externalMetricDetails(entry)

        Divider()

        Text("Storage")
          .font(.headline)
        LabeledContent(
          "Download size",
          value: ModelLibraryFormatting.megabytes(entry.descriptor.downloadBytes)
        )
        LabeledContent(
          "Installed footprint",
          value: ModelLibraryFormatting.megabytes(entry.descriptor.installedBytes)
        )
        LabeledContent(
          "Space required during install",
          value: ModelLibraryFormatting.megabytes(entry.descriptor.requiredCapacityBytes)
        )
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("models-verified-specifications")
    }

    private func externalMetricDetails(_ entry: ModelLibraryEntry) -> some View {
      let evidence = externalEvidence(for: entry)
      return VStack(alignment: .leading, spacing: 10) {
        Text("External results")
          .font(.headline)
        if let evidence {
          ForEach(evidence.metrics) { metric in
            LabeledContent(metric.label, value: metric.value)
          }
          Text(evidence.context)
            .font(.caption)
            .foregroundStyle(theme.color(.textSecondary))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("models-external-context-\(entry.id)")
          HStack(spacing: 12) {
            ForEach(evidence.sources) { source in
              Link(source.label, destination: source.url)
                .accessibilityIdentifier(
                  "models-external-source-\(entry.id)-\(source.id)"
                )
            }
          }
          .fixedSize(horizontal: false, vertical: true)
          if let accuracyContext = evidence.unmeasuredCleanupAccuracyContext {
            LabeledContent("Cleanup accuracy", value: "Not measured")
            Text(accuracyContext)
              .font(.caption)
              .foregroundStyle(theme.color(.textSecondary))
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityIdentifier("models-external-accuracy-context-\(entry.id)")
            Text(
              "The benchmark identifies the MLX model ID, not a conversion SHA, so it does not verify this pinned converted revision."
            )
            .font(.caption)
            .foregroundStyle(theme.color(.textSecondary))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("models-external-conversion-caveat-\(entry.id)")
          }
        } else {
          Text("No external results supplied.")
            .foregroundStyle(theme.color(.textSecondary))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("models-external-results")
    }

    private func attributionSection(_ entry: ModelLibraryEntry) -> some View {
      VStack(alignment: .leading, spacing: 10) {
        Text("License and attribution")
          .font(.headline)
        LabeledContent("Upstream creator", value: entry.provider.rawValue)
        LabeledContent("Converted and distributed by", value: entry.distributor)
        LabeledContent("License", value: entry.descriptor.license)
        if let licenseURL = entry.licenseURL {
          Link("Open license terms", destination: licenseURL)
            .accessibilityIdentifier("models-license-link-\(entry.id)")
        }
        Link("Open exact converted artifact", destination: entry.revisionURL)
          .accessibilityIdentifier("models-source-link-\(entry.id)")
        Link("Open upstream model card", destination: entry.modelCardURL)
          .accessibilityIdentifier("models-model-card-link-\(entry.id)")
        Button {
          attributionIsExpanded.toggle()
        } label: {
          Label(
            attributionIsExpanded ? "Hide full attribution" : "Show full attribution",
            systemImage: attributionIsExpanded ? "chevron.up" : "chevron.down"
          )
        }
        .buttonStyle(.plain)
        .accessibilityValue(attributionIsExpanded ? "Expanded" : "Collapsed")
        .accessibilityIdentifier("models-attribution-toggle")

        if attributionIsExpanded {
          VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Model ID", value: entry.descriptor.modelID)
            LabeledContent("Revision", value: entry.descriptor.revision)
            LabeledContent("Conversion", value: entry.descriptor.conversion)
            LabeledContent("Quantization", value: entry.descriptor.quantization)
            LabeledContent("Runtime ABI", value: entry.descriptor.runtimeABI)
            Text(formattedNotice(entry.descriptor.notices))
              .font(.caption)
              .fixedSize(horizontal: false, vertical: true)
              .textSelection(.enabled)
          }
          .accessibilityIdentifier("models-attribution-details")
        }

      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusBadge(_ presentation: AdmittedModelSettingsPresentation) -> some View {
      HStack(spacing: 6) {
        Circle()
          .fill(theme.color(statusColor(presentation.phase)))
          .frame(width: 7, height: 7)
          .accessibilityHidden(true)
        Text(presentation.compactStatus)
          .font(.caption.weight(.medium))
      }
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background {
        Capsule()
          .fill(theme.color(.card))
          .overlay {
            Capsule().stroke(theme.color(.border), lineWidth: 1)
          }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Installation state")
      .accessibilityValue(presentation.compactStatus)
      .accessibilityIdentifier("models-installation-status")
    }

    private func rowBackground(_ entry: ModelLibraryEntry) -> some View {
      RoundedRectangle(cornerRadius: 7, style: .continuous)
        .fill(
          selectedModelID == entry.id
            ? theme.color(.selectionFill)
            : hoveredModelID == entry.id ? theme.color(.hoverFill) : .clear
        )
    }

    private func rowFocusRing(_ entry: ModelLibraryEntry) -> some View {
      RoundedRectangle(cornerRadius: 7, style: .continuous)
        .stroke(
          focusedModelID == entry.id ? theme.color(.focusRing) : .clear,
          lineWidth: focusedModelID == entry.id ? 2 : 0
        )
    }

    private func rowAccessibilityValue(_ entry: ModelLibraryEntry) -> String {
      let evidence = externalEvidence(for: entry)
      let externalResults: String
      if let evidence {
        let metrics = evidence.metrics
          .map { "\($0.label): \(compactExternalMetricValue($0.value))" }
          .joined(separator: "; ")
        let hardware = externalHardwareQualifier(for: evidence)
          .map { " on \($0)" } ?? ""
        let accuracy = evidence.unmeasuredCleanupAccuracyContext == nil
          ? ""
          : "; Cleanup accuracy: Not measured"
        externalResults = "External benchmark\(hardware): \(metrics)\(accuracy)"
      } else {
        externalResults = "No external results supplied"
      }
      let identity = "\(entry.provider.rawValue), \(entry.typeTitle), \(entry.presentation.compactStatus)"
      let downloadSize = ModelLibraryFormatting.megabytes(entry.descriptor.downloadBytes)
      return "\(identity), download size \(downloadSize), \(externalResults)"
    }

    private func externalEvidence(for entry: ModelLibraryEntry) -> ModelLibraryExternalEvidence? {
      ModelLibraryExternalEvidenceCatalog.evidence(for: entry.descriptor)
    }

    private func compactExternalMetricValue(_ value: String) -> String {
      value.replacingOccurrences(of: "tokens/s", with: "tok/s")
    }

    private func externalHardwareQualifier(
      for evidence: ModelLibraryExternalEvidence
    ) -> String? {
      ["M4 Pro", "M4 Max"].first { evidence.context.contains($0) }
    }

    private func sortByNameButton(title: String) -> some View {
      Button {
        sortAscending.toggle()
      } label: {
        HStack(spacing: 5) {
          Text(title)
          Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
            .font(.caption2.weight(.semibold))
        }
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Sort by model name")
      .accessibilityValue(sortAscending ? "A to Z" : "Z to A")
      .accessibilityHint("Pinned models remain first in either order.")
      .accessibilityIdentifier("models-sort-name")
    }

    private func detailColor(_ phase: AdmittedModelInstallPhase) -> Color {
      theme.color(statusColor(phase))
    }

    private func statusColor(_ phase: AdmittedModelInstallPhase) -> FleckThemeColor {
      switch phase {
      case .installed:
        .success
      case .updateAvailable, .repairRequired, .cancelled:
        .warning
      case .failed:
        .error
      case .downloading, .verifying, .installing, .ready, .starting, .calibrating, .removing:
        .accent
      case .builtIn, .notInstalled:
        .textSecondary
      }
    }

    private func actionTitle(
      _ action: AdmittedModelSettingsAction,
      presentation: AdmittedModelSettingsPresentation,
      installLabel: String
    ) -> String {
      if presentation.primaryActionLabel == "Retry" {
        return "Retry"
      }
      return switch action {
      case .install: installLabel
      case .cancel: "Cancel"
      case .repair: "Repair"
      case .update: "Update"
      case .remove: "Remove"
      }
    }

    private func actionHint(
      _ action: AdmittedModelSettingsAction,
      model: ModelLibraryEntry
    ) -> String {
      switch action {
      case .install:
        "Downloads \(model.title). Fleck uses it automatically only while it is installed and healthy."
      case .cancel:
        "Cancels the current installation."
      case .repair:
        "Repairs the local installation before Fleck can use it."
      case .update:
        "Updates the local model. Fleck continues to choose its runtime automatically."
      case .remove:
        "Asks before removal and explains the local fallback."
      }
    }

    private func perform(_ action: AdmittedModelSettingsAction, for entry: ModelLibraryEntry) {
      switch action {
      case .remove:
        pendingRemoval = entry
      case .install, .repair, .update:
        pendingInstallReview = PendingModelInstallReview(entry: entry, action: action)
      case .cancel:
        entry.viewModel.perform(action)
      }
    }

    private func openDetails(_ entry: ModelLibraryEntry) {
      setSelectedModelID(entry.id)
      focusedModelID = nil
    }

    private func closeDetails() {
      guard let selectedModelID else { return }
      setSelectedModelID(nil)
      focusedModelID = selectedModelID
    }

    private func clearFilters() {
      searchQuery = ""
      providerFilter = "all"
      modelTypeFilterBinding.wrappedValue = .all
      searchIsFocused = true
    }

    private func updateHover(_ id: String, inside: Bool) {
      if inside {
        hoveredModelID = id
      } else if hoveredModelID == id {
        hoveredModelID = nil
      }
    }

    private func moveRowFocus(
      _ direction: MoveCommandDirection,
      in entries: [ModelLibraryEntry],
      proxy: ScrollViewProxy
    ) {
      guard let focusedModelID,
            let index = entries.firstIndex(where: { $0.id == focusedModelID }) else {
        return
      }
      let destination: Int
      switch direction {
      case .up:
        destination = index - 1
      case .down:
        destination = index + 1
      default:
        return
      }
      guard entries.indices.contains(destination) else { return }
      let nextID = entries[destination].id
      self.focusedModelID = nextID
      proxy.scrollTo(nextID, anchor: .center)
    }
  }

  @MainActor
  private struct PendingModelInstallReview: Identifiable {
    let entry: ModelLibraryEntry
    let action: AdmittedModelSettingsAction
    nonisolated let id: String

    var requiresTermsAcceptance: Bool {
      ModelLibraryCatalog.requiresTermsReview(for: action, descriptor: entry.descriptor)
    }

    init(entry: ModelLibraryEntry, action: AdmittedModelSettingsAction) {
      self.entry = entry
      self.action = action
      id = entry.id
    }
  }

  private struct ModelInstallReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fleckThemeSnapshot) private var theme
    let entry: ModelLibraryEntry
    let action: AdmittedModelSettingsAction
    let requiresTermsAcceptance: Bool
    let onContinue: () -> Void

    private var title: String {
      if requiresTermsAcceptance {
        return "Review Gemma Terms of Use"
      }
      switch action {
      case .install:
        return "Review model download"
      case .update:
        return "Review model update"
      case .repair:
        return "Review model repair"
      case .cancel, .remove:
        return "Review model action"
      }
    }

    private var summary: String {
      if requiresTermsAcceptance {
        return "Gemma is custom-licensed third-party material and is not covered by Fleck’s MPL-2.0 license. Installing or using this model locally constitutes acceptance of its terms."
      }
      return "Review the exact converted model, its license, and the storage required on this Mac before continuing."
    }

    private var continueTitle: String {
      let verb: String
      switch action {
      case .install:
        verb = "Download"
      case .update:
        verb = "Update"
      case .repair:
        verb = "Repair"
      case .cancel, .remove:
        verb = "Continue"
      }
      return requiresTermsAcceptance ? "Accept and \(verb)" : "\(verb) Model"
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 16) {
        Text(title)
          .font(.title2.weight(.semibold))
        Text(summary)
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        ScrollView {
          VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Upstream creator", value: entry.provider.rawValue)
            LabeledContent("Converted and distributed by", value: entry.distributor)
            LabeledContent("License", value: entry.descriptor.license)
              .accessibilityIdentifier("models-install-review-license")
            LabeledContent(
              "Download size",
              value: ModelLibraryFormatting.megabytes(entry.descriptor.downloadBytes)
            )
            LabeledContent(
              "Installed footprint",
              value: ModelLibraryFormatting.megabytes(entry.descriptor.installedBytes)
            )
            LabeledContent(
              "Space required during install",
              value: ModelLibraryFormatting.megabytes(entry.descriptor.requiredCapacityBytes)
            )
            .accessibilityIdentifier("models-install-review-required-capacity")
            Link("Open exact converted artifact", destination: entry.revisionURL)
              .accessibilityIdentifier("models-install-review-source")
            Link("Open upstream model card", destination: entry.modelCardURL)
            if let licenseURL = entry.licenseURL {
              Link("Open license terms", destination: licenseURL)
                .accessibilityIdentifier("models-install-review-license-link")
            }
            Text(formattedNotice(entry.descriptor.notices))
              .font(.callout)
              .frame(maxWidth: .infinity, alignment: .leading)
              .textSelection(.enabled)
              .accessibilityIdentifier("models-install-review-notice")
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(theme.color(.window))
        .accessibilityIdentifier("models-install-review-details")
        HStack {
          Button("Cancel", role: .cancel) { dismiss() }
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("models-install-review-cancel")
          Spacer()
          Button(continueTitle) {
            onContinue()
            dismiss()
          }
          .keyboardShortcut(.defaultAction)
          .accessibilityIdentifier("models-install-review-continue")
        }
      }
      .padding(24)
      .frame(minWidth: 520, idealWidth: 600, minHeight: 460, idealHeight: 540)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("models-install-review")
    }
  }

  private enum ModelLibraryFormatting {
    static func megabytes(_ bytes: Int64) -> String {
      let formatter = ByteCountFormatter()
      formatter.allowedUnits = [.useMB]
      formatter.countStyle = .decimal
      formatter.includesActualByteCount = false
      return formatter.string(fromByteCount: bytes)
    }
  }

  private func formattedNotice(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text)) ?? AttributedString(text)
  }
#endif
