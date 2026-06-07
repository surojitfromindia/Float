import SwiftData
import SwiftUI

struct EventsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \EventCategoryItem.sortOrder) private var categories: [EventCategoryItem]
    @State private var events: [EventItem] = []
    @State private var nextPageOffset = 0
    @State private var isLoadingPage = false
    @State private var hasMorePages = true
    @State private var pageError: String?
    @State private var searchText = ""
    @State private var selectedStatus = EventStatusFilter.all
    @State private var useDateRange = false
    @State private var startDate = Calendar.current.date(
        byAdding: .month,
        value: -1,
        to: Date()
    ) ?? Date()
    @State private var endDate = Date()
    @State private var showingFilters = false
    @State private var editorPresentation: EventEditorPresentation?
    @State private var pendingDeleteEvent: EventItem?
    @State private var showingDeleteAlert = false

    private var filteredEvents: [EventItem] {
        events.filter(matchesEvent).sorted {
            $0.startDate > $1.startDate
        }
    }

    private var hasActiveFilters: Bool {
        selectedStatus != .all || useDateRange
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                compactFilterSection

                if filteredEvents.isEmpty && !isLoadingPage {
                    EmptyStateView(
                        icon: "calendar.badge.plus",
                        title: emptyStateTitle,
                        message: emptyStateMessage
                    )
                    .transactionPlainSurface(cornerRadius: FloatTheme.controlRadius)
                } else {
                    ForEach(filteredEvents) { event in
                        NavigationLink {
                            EventDetailView(event: event)
                        } label: {
                            EventRowView(event: event)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                editorPresentation = EventEditorPresentation(event: event)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                pendingDeleteEvent = event
                                showingDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .onAppear {
                            loadOlderPageIfNeeded(afterDisplaying: event)
                        }
                    }
                    paginationFooter
                }
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .navigationTitle("Events")
        .searchable(text: $searchText, prompt: "Search events")
        .keyboardDismissControls()
        .floatBackground()
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink {
                    EventSettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Event settings")

                Button {
                    editorPresentation = EventEditorPresentation(event: nil)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add event")
            }
        }
        .sheet(item: $editorPresentation, onDismiss: resetAndLoadFirstPage) { presentation in
            EventEditorSheet(
                eventToEdit: presentation.event,
                categories: categories,
                onSave: resetAndLoadFirstPage
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingFilters) {
            EventListFilterSheet(
                selectedStatus: $selectedStatus,
                useDateRange: $useDateRange,
                startDate: $startDate,
                endDate: $endDate,
                hasActiveFilters: hasActiveFilters,
                clearFilters: clearFilters
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert("Delete event?", isPresented: $showingDeleteAlert, presenting: pendingDeleteEvent) { event in
            Button("Cancel", role: .cancel) {}
            Button("Delete event", role: .destructive) {
                delete(event)
            }
        } message: { event in
            Text(
                "Deleting \(event.name) will remove the event from Float, but its transactions will stay in your ledger."
            )
        }
        .task {
            resetAndLoadFirstPage()
        }
        .onChange(of: searchText) { _, _ in resetAndLoadFirstPage() }
        .onChange(of: selectedStatus) { _, _ in resetAndLoadFirstPage() }
        .onChange(of: useDateRange) { _, _ in resetAndLoadFirstPage() }
        .onChange(of: startDate) { _, newValue in
            if newValue > endDate { endDate = newValue }
            if useDateRange { resetAndLoadFirstPage() }
        }
        .onChange(of: endDate) { _, newValue in
            if newValue < startDate { startDate = newValue }
            if useDateRange { resetAndLoadFirstPage() }
        }
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if let pageError {
            Button {
                loadOlderPage()
            } label: {
                Label(pageError, systemImage: "arrow.clockwise")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        } else if hasMorePages {
            HStack(spacing: 10) {
                if isLoadingPage {
                    ProgressView()
                }
                Text(isLoadingPage ? "Loading older events" : "Load older events")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .onAppear {
                loadOlderPage()
            }
        }
    }

    private var emptyStateTitle: String {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !hasActiveFilters {
            return "No events yet"
        }
        return "No matching events"
    }

    private var emptyStateMessage: String {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !hasActiveFilters {
            return "Create an event to group transactions, metrics, and charts."
        }
        return "Try a different search or filter."
    }

    private var compactFilterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Menu {
                    Picker("Status", selection: $selectedStatus) {
                        ForEach(EventStatusFilter.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                } label: {
                    FilterControlLabel(
                        title: selectedStatus.title,
                        icon: "calendar.badge.exclamationmark"
                    )
                }

                Spacer(minLength: 0)

                Button {
                    showingFilters = true
                } label: {
                    FilterControlLabel(
                        title: "Filters",
                        icon: hasActiveFilters
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle"
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 2)

            if hasActiveFilters {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(activeFilterChips) { chip in
                            Button {
                                removeFilter(chip.kind)
                            } label: {
                                HStack(spacing: 5) {
                                    Text(chip.title)
                                    Image(systemName: "xmark")
                                        .font(.caption2.weight(.bold))
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 2)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }

                        Button("Clear", action: clearFilters)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 2)
                            .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    private var activeFilterChips: [EventFilterChip] {
        var chips: [EventFilterChip] = []
        if selectedStatus != .all {
            chips.append(EventFilterChip(title: selectedStatus.title, kind: .status))
        }
        if useDateRange {
            chips.append(
                EventFilterChip(
                    title: "\(startDate.formatted(date: .abbreviated, time: .omitted)) - \(endDate.formatted(date: .abbreviated, time: .omitted))",
                    kind: .dateRange
                )
            )
        }
        return chips
    }

    private func matchesEvent(_ event: EventItem) -> Bool {
        let query = normalizedSearchText
        let matchesSearch = query.isEmpty
            || event.name.localizedCaseInsensitiveContains(query)
            || (event.eventDescription ?? "").localizedCaseInsensitiveContains(query)
            || (event.category?.name ?? "").localizedCaseInsensitiveContains(query)

        let matchesStatus = selectedStatus == .all || event.status.rawValue == selectedStatus.rawValue
        let matchesDate = !useDateRange
            || event.startDate <= endDate.endOfDay
            && event.endDate >= startDate.startOfDay
        return matchesSearch && matchesStatus && matchesDate
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resetAndLoadFirstPage() {
        events = []
        nextPageOffset = 0
        hasMorePages = true
        pageError = nil
        loadOlderPage()
    }

    private func loadOlderPage() {
        guard !isLoadingPage, hasMorePages else { return }
        isLoadingPage = true
        pageError = nil

        do {
            let descriptor = eventPageDescriptor(offset: nextPageOffset)
            let fetched = try modelContext.fetch(descriptor)
            mergeLoadedEvents(fetched)
            nextPageOffset += fetched.count
            hasMorePages = fetched.count == 100
            isLoadingPage = false
        } catch {
            pageError = "Could not load older events"
            isLoadingPage = false
        }
    }

    private func loadOlderPageIfNeeded(afterDisplaying event: EventItem) {
        guard shouldLoadOlderPage(afterDisplaying: event) else { return }
        loadOlderPage()
    }

    private func shouldLoadOlderPage(afterDisplaying event: EventItem) -> Bool {
        guard hasMorePages, !isLoadingPage, pageError == nil else { return false }
        let triggerItems = filteredEvents.suffix(5)
        return triggerItems.contains { $0.id == event.id }
    }

    private func eventPageDescriptor(offset: Int) -> FetchDescriptor<EventItem> {
        var descriptor = FetchDescriptor<EventItem>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = 100
        descriptor.fetchOffset = offset
        return descriptor
    }

    private func mergeLoadedEvents(_ items: [EventItem]) {
        var existingIDs = Set(events.map(\.id))
        for item in items where !existingIDs.contains(item.id) {
            events.append(item)
            existingIDs.insert(item.id)
        }
    }

    private func delete(_ event: EventItem) {
        do {
            try EventRepository(modelContext: modelContext).delete(event)
            if pendingDeleteEvent?.id == event.id {
                pendingDeleteEvent = nil
            }
            resetAndLoadFirstPage()
        } catch {
            pageError = error.localizedDescription
        }
    }

    private func clearFilters() {
        selectedStatus = .all
        useDateRange = false
    }

    private func removeFilter(_ kind: EventFilterChip.Kind) {
        switch kind {
        case .status:
            selectedStatus = .all
        case .dateRange:
            useDateRange = false
        }
    }
}

struct EventRowView: View {
    let event: EventItem
    var showsDescription: Bool = true

    private var palette: Color {
        Color(hex: event.category?.colorHex ?? "#0E7C7B")
    }

    private var statusTint: Color {
        event.isActive ? Color(hex: "#1B8A5A") : Color(hex: "#B4613B")
    }

    var body: some View {
        GlassCard(padding: 16) {
            HStack(alignment: .top, spacing: 12) {
                FloatIconBadge(
                    icon: event.category?.iconKey ?? "calendar",
                    tint: palette,
                    size: 38
                )

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(event.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if event.pinned {
                            Image(systemName: "pin.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(appStatePinnedColor)
                        }
                    }

                    Text(eventDateRangeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let category = event.category {
                        Text(category.name)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(palette)
                    }

                    if showsDescription, let description = event.eventDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 8) {
                    Text(event.status.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusTint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(statusTint.opacity(0.12), in: Capsule())

                    Text("\(event.transactions.count) tx")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var appStatePinnedColor: Color {
        Color(hex: "#0A6FAE")
    }

    private var eventDateRangeText: String {
        "\(event.startDate.formatted(date: .abbreviated, time: .omitted)) - \(event.endDate.formatted(date: .abbreviated, time: .omitted))"
    }
}

struct EventSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List {
            Section("Preferences") {
                Toggle("Show pinned events in home view", isOn: $appState.showPinnedEventsInHomeView)
            }
            Section("Manage") {
                NavigationLink("Event categories") {
                    EventCategoryManagerView()
                }
            }
        }
        .navigationTitle("Event Settings")
        .scrollContentBackground(.hidden)
        .floatBackground()
    }
}

struct EventCategoryManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \EventCategoryItem.sortOrder) private var categories: [EventCategoryItem]
    @Query(sort: \EventItem.startDate, order: .reverse) private var events: [EventItem]
    @State private var editorPresentation: EventCategoryEditorPresentation?

    private var usedCategoryIDs: Set<UUID> {
        Set(events.compactMap { $0.category?.id })
    }

    var body: some View {
        List {
            ForEach(categories) { category in
                Button {
                    editorPresentation = EventCategoryEditorPresentation(
                        category: category,
                        canDelete: !usedCategoryIDs.contains(category.id)
                    )
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    Color(hex: category.colorHex).opacity(0.16)
                                )
                            Image(systemName: category.iconKey)
                                .foregroundStyle(Color(hex: category.colorHex))
                        }
                        .frame(width: 36, height: 36)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(category.name)
                                .font(.headline)
                            Text(usedCategoryIDs.contains(category.id) ? "In use" : "Unused")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Event Categories")
        .scrollContentBackground(.hidden)
        .floatBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorPresentation = EventCategoryEditorPresentation(
                        category: nil,
                        canDelete: false
                    )
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add event category")
            }
        }
        .sheet(item: $editorPresentation) { presentation in
            EventCategoryEditorView(
                category: presentation.category,
                canDelete: presentation.canDelete,
                nextSortOrder: categories.count
            )
        }
    }
}

private struct EventEditorPresentation: Identifiable {
    let id = UUID()
    let event: EventItem?
}

private struct EventCategoryEditorPresentation: Identifiable {
    let id = UUID()
    let category: EventCategoryItem?
    let canDelete: Bool
}

private struct EventCategoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let category: EventCategoryItem?
    let canDelete: Bool
    let nextSortOrder: Int

    @State private var name = ""
    @State private var iconKey = "calendar"
    @State private var colorHex = "#0E7C7B"

    private let iconOptions = [
        "calendar", "calendar.badge.plus", "calendar.badge.exclamationmark",
        "star.fill", "flag.fill", "briefcase.fill", "gift.fill", "party.popper.fill",
        "airplane", "car.fill", "house.fill", "building.2.fill", "graduationcap.fill",
        "heart.fill", "bed.double.fill", "wand.and.stars", "sparkles",
        "fork.knife", "music.note", "camera.fill", "ticket.fill",
    ]

    private let colorOptions = [
        "#0E7C7B", "#14B8A6", "#0EA5E9", "#3B82F6",
        "#2563EB", "#6366F1", "#7C3AED", "#8B5CF6",
        "#A855F7", "#C026D3", "#DB2777", "#EC4899",
        "#F43F5E", "#EF4444", "#F97316", "#F59E0B",
        "#B4613B", "#D08A62", "#84CC16", "#22C55E",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                }

                Section("Icon") {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 44))],
                        spacing: 12
                    ) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Button {
                                iconKey = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.headline)
                                    .frame(width: 42, height: 42)
                                    .background(
                                        iconKey == icon
                                            ? Color(hex: colorHex).opacity(0.2)
                                            : Color.primary.opacity(0.06),
                                        in: Circle()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Color") {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 34))],
                        spacing: 12
                    ) {
                        ForEach(colorOptions, id: \.self) { color in
                            Button {
                                colorHex = color
                            } label: {
                                Circle()
                                    .fill(Color(hex: color))
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(
                                                Color.primary.opacity(colorHex == color ? 0.2 : 0),
                                                lineWidth: 3
                                            )
                                    )
                                    .overlay {
                                        if colorHex == color {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    TextField("Hex color", text: $colorHex)
                        .textInputAutocapitalization(.characters)
                }

                if category != nil, canDelete {
                    Section {
                        Button("Delete event category", role: .destructive, action: delete)
                    }
                }
            }
            .navigationTitle(category == nil ? "New Category" : "Edit Category")
            .keyboardDismissControls()
            .scrollContentBackground(.hidden)
            .floatBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(
                            name.trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                        )
                }
            }
            .onAppear(perform: configure)
        }
    }

    private func configure() {
        guard let category else { return }
        name = category.name
        iconKey = category.iconKey
        colorHex = category.colorHex
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let category {
                try EventCategoryRepository(modelContext: modelContext).update(
                    category,
                    name: trimmedName,
                    iconKey: iconKey,
                    colorHex: colorHex
                )
            } else {
                _ = try EventCategoryRepository(modelContext: modelContext).create(
                    name: trimmedName,
                    iconKey: iconKey,
                    colorHex: colorHex,
                    sortOrder: nextSortOrder
                )
            }
            dismiss()
        } catch {
            // Keep the sheet open if save fails.
        }
    }

    private func delete() {
        guard let category else { return }
        do {
            _ = try EventCategoryRepository(modelContext: modelContext)
                .deleteIfUnused(category)
            dismiss()
        } catch {
            // Keep the sheet open if delete fails.
        }
    }
}

struct EventEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    let eventToEdit: EventItem?
    let categories: [EventCategoryItem]
    let onSave: () -> Void

    @State private var name = ""
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var status = EventStatus.active
    @State private var eventDescription = ""
    @State private var selectedCategory: EventCategoryItem?
    @State private var pinned = false
    @State private var validationMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Event name", text: $name)
                    Picker("Status", selection: $status) {
                        ForEach(EventStatus.allCases) { status in
                            Text(status.title).tag(status)
                        }
                    }
                    Picker("Category", selection: $selectedCategory) {
                        Text("No category").tag(EventCategoryItem?.none)
                        ForEach(categories) { category in
                            Text(category.name).tag(Optional(category))
                        }
                    }
                }

                Section("Dates") {
                    DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                    DatePicker("End date", selection: $endDate, displayedComponents: .date)
                }

                Section("Description") {
                    TextField("Description", text: $eventDescription, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }

                Section("Home") {
                    Toggle("Pin event", isOn: $pinned)
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .font(.footnote)
                            .foregroundStyle(appState.themePalette.caution)
                    }
                }
            }
            .navigationTitle(eventToEdit == nil ? "Add Event" : "Edit Event")
            .keyboardDismissControls()
            .scrollContentBackground(.hidden)
            .floatBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear(perform: configure)
            .onChange(of: startDate) { _, newValue in
                if newValue > endDate {
                    endDate = newValue
                }
            }
            .onChange(of: endDate) { _, newValue in
                if newValue < startDate {
                    startDate = newValue
                }
            }
        }
    }

    private func configure() {
        guard let eventToEdit else { return }
        name = eventToEdit.name
        startDate = eventToEdit.startDate
        endDate = eventToEdit.endDate
        status = eventToEdit.status
        eventDescription = eventToEdit.eventDescription ?? ""
        selectedCategory = eventToEdit.category
        pinned = eventToEdit.pinned
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationMessage = "Enter an event name."
            return
        }

        do {
            if let eventToEdit {
                try EventRepository(modelContext: modelContext).update(
                    eventToEdit,
                    name: trimmedName,
                    startDate: startDate,
                    endDate: endDate,
                    status: status,
                    category: selectedCategory,
                    eventDescription: eventDescription,
                    pinned: pinned
                )
            } else {
                _ = try EventRepository(modelContext: modelContext).create(
                    name: trimmedName,
                    startDate: startDate,
                    endDate: endDate,
                    status: status,
                    category: selectedCategory,
                    eventDescription: eventDescription,
                    pinned: pinned
                )
            }
            onSave()
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}

private struct EventListFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedStatus: EventStatusFilter
    @Binding var useDateRange: Bool
    @Binding var startDate: Date
    @Binding var endDate: Date
    let hasActiveFilters: Bool
    let clearFilters: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    filterHeader

                    filterSection(title: "Filters", icon: "line.3.horizontal.decrease.circle") {
                        VStack(spacing: 10) {
                            menuRow(
                                title: "Status",
                                value: selectedStatus.title,
                                icon: "calendar.badge.exclamationmark"
                            ) {
                                Picker("Status", selection: $selectedStatus) {
                                    ForEach(EventStatusFilter.allCases) {
                                        Text($0.title).tag($0)
                                    }
                                }
                            }

                            Divider()

                            Toggle(isOn: $useDateRange) {
                                filterRowLabel(title: "Date range", icon: "calendar")
                            }
                            .tint(Color(hex: "#0A6FAE"))
                            .padding(.vertical, 8)

                            if useDateRange {
                                Divider()
                                dateRow(title: "From", selection: $startDate)
                                Divider()
                                dateRow(title: "To", selection: $endDate)
                            }
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDismissControls()
            .scrollContentBackground(.hidden)
            .floatBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var filterHeader: some View {
        GlassCard {
            HStack(spacing: 12) {
                FloatIconBadge(
                    icon: hasActiveFilters
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle",
                    tint: Color(hex: "#0A6FAE"),
                    size: 40
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(hasActiveFilters ? "Filters active" : "All events")
                        .font(.headline)
                    Text(filterSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }
        }
    }

    private var filterSummary: String {
        var parts: [String] = []
        if selectedStatus != .all { parts.append(selectedStatus.title) }
        if useDateRange { parts.append("Date range") }
        return parts.isEmpty ? "No filters are applied." : parts.joined(separator: " • ")
    }

    private func filterSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.secondary)
            content()
                .padding(.vertical, 2)
        }
    }

    private func filterRowLabel(title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            FloatIconBadge(icon: icon, tint: Color(hex: "#0A6FAE"), size: 34)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }

    private func dateRow(
        title: String,
        selection: Binding<Date>
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            DatePicker(
                title,
                selection: selection,
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .fixedSize()
        }
        .padding(.vertical, 8)
    }

    private func menuRow<MenuContent: View>(
        title: String,
        value: String,
        icon: String,
        @ViewBuilder menuContent: () -> MenuContent
    ) -> some View {
        HStack(spacing: 12) {
            FloatIconBadge(icon: icon, tint: Color(hex: "#0A6FAE"), size: 34)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            Menu {
                menuContent()
            } label: {
                HStack(spacing: 8) {
                    Text(value)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(hex: "#0A6FAE"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color(hex: "#0A6FAE"))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }
}

private enum EventStatusFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case ended

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .active: "Active"
        case .ended: "Ended"
        }
    }
}

private struct EventFilterChip: Identifiable {
    let id = UUID()
    let title: String
    let kind: Kind

    enum Kind {
        case status
        case dateRange
    }
}

private extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    var endOfDay: Date {
        Calendar.current.date(
            byAdding: DateComponents(day: 1, second: -1),
            to: Calendar.current.startOfDay(for: self)
        ) ?? self
    }
}

private struct FilterControlLabel: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 2)
            .padding(.vertical, 8)
    }
}

private extension View {
    func transactionPlainSurface(
        cornerRadius: CGFloat,
        tint: Color? = nil
    ) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: cornerRadius,
            style: .continuous
        )

        return self
            .background(
                Color(.secondarySystemGroupedBackground),
                in: shape
            )
            .background(
                (tint ?? Color.clear).opacity(tint == nil ? 0 : 0.08),
                in: shape
            )
            .overlay(
                shape.strokeBorder(
                    (tint ?? Color.primary).opacity(tint == nil ? 0.06 : 0.14),
                    lineWidth: 1
                )
            )
    }
}
