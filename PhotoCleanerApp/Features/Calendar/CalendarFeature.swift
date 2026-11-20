import SwiftUI
import EventKit
import Observation

nonisolated private struct CalendarSnapshot: Hashable, Sendable {
    let calendarIdentifier: String
    let title: String
    let allowsContentModifications: Bool
    let red: Double
    let green: Double
    let blue: Double
    var cgColor: CGColor { CGColor(red: red, green: green, blue: blue, alpha: 1) }
}

private struct CalendarOutcome {
    let title: String
    let message: String
}

struct CalendarScreen: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State var model: CalendarStore
    @State private var confirm = false
    @State private var deleteErrorAlert = false
    @State private var outcome: CalendarOutcome?
    @Environment(\.scenePhase) private var scenePhase
    let displayedCount: Int?
    let displayedYearCounts: [Int: Int]
    init(model: CalendarStore? = nil, displayedCount: Int? = nil, displayedYearCounts: [Int: Int] = [:], resultTitle: String? = nil, resultMessage: String = "") {
        _model = State(initialValue: model ?? CalendarStore())
        self.displayedCount = displayedCount; self.displayedYearCounts = displayedYearCounts
        _outcome = State(initialValue: resultTitle.map { CalendarOutcome(title: $0, message: resultMessage) })
    }
    private var groups: [Int] { Array(Set(model.events.map { Calendar.current.component(.year, from: $0.startDate) })).sorted { model.future ? $0 < $1 : $0 > $1 } }
    private func events(in year: Int) -> [EventSnapshot] {
        model.events.filter { Calendar.current.component(.year, from: $0.startDate) == year }.sorted { model.future ? $0.startDate < $1.startDate : $0.startDate > $1.startDate }
    }
    private var writable: Set<String> { Set(model.events.filter { $0.calendar.allowsContentModifications }.map(\.stableID)) }
    private var allSelected: Bool { !writable.isEmpty && writable.isSubset(of: model.selected) }
    private var selectionCount: Int { model.preview && allSelected ? (displayedCount ?? model.selected.count) : model.selected.count }
    private var buttonTitle: String { selectionCount == 0 ? "Delete events" : "Delete \(selectionCount) Event\(selectionCount == 1 ? "" : "s")" }
    var body: some View {
        VStack(spacing: 0) {
            HeaderView(title: "Calendar")
            VStack(spacing: 16) {
                HStack(spacing: 0) {
                    ForEach([false, true], id: \.self) { future in
                        Button { model.future = future } label: {
                            Text(future ? "Future" : "Past").font(Palette.font(16, .semibold)).frame(maxWidth: .infinity, minHeight: 32)
                                .foregroundStyle(model.future == future ? Palette.blue : Palette.secondary)
                                .background(model.future == future ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain).accessibilityAddTraits(model.future == future ? .isSelected : [])
                    }
                }.padding(8).background(Color(hex: 0xE5EBF5), in: RoundedRectangle(cornerRadius: 16)).disabled(model.working)
                if model.loading { ProgressView("Loading events…").frame(maxWidth: .infinity, maxHeight: .infinity) }
                else if !model.allowed {
                    EmptyState(title: "Allow calendar access", message: "Allow access to your calendar to review events.", systemImage: "calendar")
                    Button("Go to Settings", action: openSettings)
                    Spacer(minLength: 0)
                } else {
                    HStack {
                        Text("\(displayedCount ?? model.events.count) events").foregroundStyle(Palette.secondary)
                        Spacer()
                        if !model.events.isEmpty {
                            Button(allSelected ? "Deselect all" : "Select all") { model.selected = allSelected ? [] : writable }
                                .font(Palette.font(16, .semibold)).foregroundStyle(Palette.blue)
                                .padding(.vertical, 10).contentShape(Rectangle()).padding(.vertical, -10)
                        }
                    }.frame(minHeight: 24).disabled(model.working)
                    if model.events.isEmpty && model.error == nil {
                        ScrollView {
                          VStack(spacing: 8) {
                            Image("EmptyCalendar").resizable().scaledToFit().frame(maxWidth: 312).frame(height: 264).accessibilityHidden(true)
                            Text(model.future ? "No future events" : "No past events").font(Palette.font(24, .semibold)).fixedSize(horizontal: false, vertical: true)
                            Text(model.future ? (dynamicType.isAccessibilitySize ? "— New events from your calendars will appear here." : "— New events from your calendars will appear\nhere.") : "— When an event ends, it will appear here.")
                                .cleanerBodyLineHeight().foregroundStyle(Palette.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                          }.multilineTextAlignment(.center).frame(maxWidth: .infinity)
                        }.defaultScrollAnchor(dynamicType.isAccessibilitySize ? .top : .center)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(groups, id: \.self) { year in
                                    let layout = dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
                                    layout {
                                        Text(String(year)).font(Palette.font(24, .semibold)).fixedSize()
                                        Text("\(displayedYearCounts[year] ?? events(in: year).count) events").foregroundStyle(Palette.secondary)
                                    }.frame(minHeight: 40)
                                    ForEach(events(in: year), id: \.stableID) { event in eventRow(event) }
                                }
                            }
                        }
                    }
                }
            }.padding(.horizontal, 16).padding(.top, 16).frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.allowed && !model.loading && !model.events.isEmpty {
                PrimaryButton(title: model.working ? "Deleting…" : buttonTitle, disabled: model.selected.isEmpty || model.working) { confirm = true }
                    .padding(16)
            }
        }.background(Palette.bg.ignoresSafeArea()).foregroundStyle(Palette.ink).font(Palette.font(16)).toolbar(.hidden, for: .navigationBar)
            .task { await model.load() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.load() } } }
            .onChange(of: model.future) { _, _ in model.selected.removeAll(); model.result = nil; Task { await model.load() } }
            .alert("Delete \(model.selected.count) event\(model.selected.count == 1 ? "" : "s")?", isPresented: $confirm) {
                Button("Delete", role: .destructive) {
                    Task {
                        await model.delete()
                        if model.error != nil {
                            deleteErrorAlert = true
                        } else if model.deletedCount > 0 {
                            outcome = CalendarOutcome(title: "\(model.deletedCount) event\(model.deletedCount == 1 ? "" : "s") deleted", message: model.future ? "Upcoming events" : "Past events")
                        }
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: { Text("They will be removed from all your devices.") }
            .alert("Couldn't delete events", isPresented: $deleteErrorAlert) {
                Button("Try again") {
                    Task {
                        await model.delete()
                        if model.error != nil {
                            deleteErrorAlert = true
                        } else if model.deletedCount > 0 {
                            outcome = CalendarOutcome(title: "\(model.deletedCount) event\(model.deletedCount == 1 ? "" : "s") deleted", message: model.future ? "Upcoming events" : "Past events")
                        }
                    }
                }
                Button("Cancel", role: .cancel) { }
            }
            .overlay {
                if let outcome {
                    NoticeView(title: outcome.title, message: outcome.message, asset: "CalendarSuccess", onPrimary: { self.outcome = nil })
                }
            }
    }
    private func eventRow(_ event: EventSnapshot) -> some View {
        Button {
            if model.selected.contains(event.stableID) { model.selected.remove(event.stableID) } else { model.selected.insert(event.stableID) }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(event.title ?? "Untitled event").font(Palette.font(16, .semibold)).frame(minHeight: 24).fixedSize(horizontal: false, vertical: true)
                    let layout = dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 8))
                    layout {
                        Text(event.startDate.formatted(.dateTime.month(.abbreviated).day())).fixedSize()
                        Circle().fill(Color(cgColor: event.calendar.cgColor)).frame(width: 8, height: 8)
                        Text(event.calendar.title).lineLimit(dynamicType.isAccessibilitySize ? nil : 1).fixedSize(horizontal: false, vertical: true)
                    }.font(Palette.font(16)).frame(minHeight: 24).foregroundStyle(Palette.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                ContactCheck(selected: model.selected.contains(event.stableID))
            }.padding(.horizontal, 16).padding(.vertical, 8).frame(minHeight: 64).background(.white, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(Palette.ink)
        }.buttonStyle(.plain).disabled(model.working).accessibilityAddTraits(model.selected.contains(event.stableID) ? .isSelected : [])
    }
}

struct CalendarFidelityScreen: View {
    @State private var model = CalendarStore()
    @State private var ready = false
    private var result: (String?, String) {
        let texts = FidelityPreview.texts
        guard texts.last == "Continue", texts.count >= 3 else { return (nil, "") }
        return (texts[texts.count - 3], texts[texts.count - 2])
    }
    private var count: Int {
        FidelityPreview.texts.first(where: { $0.hasSuffix(" events") && Int($0.split(separator: " ").first ?? "") != nil }).flatMap { Int($0.split(separator: " ")[0]) } ?? 0
    }
    var body: some View {
        Group {
            if ready {
                CalendarScreen(model: model, displayedCount: count, displayedYearCounts: model.future ? [2026: 5, 2027: 7] : [2026: 103, 2025: 122, 2024: 115], resultTitle: result.0, resultMessage: result.1)
            } else { Color.clear }
        }.task {
            guard FidelityPreview.active, !ready else { return }
            #if DEBUG
            model.preview = true; model.allowed = true; model.future = FidelityPreview.name.contains("Future")
            let texts = FidelityPreview.texts
            var year = 2026
            var generated: [EventSnapshot] = []
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "MMM d yyyy"
            for index in texts.indices {
                if let value = Int(texts[index]), (2020...2100).contains(value) { year = value }
                guard index + 2 < texts.count, let date = formatter.date(from: texts[index + 1] + " \(year)"), ["Work", "Personal", "Family"].contains(texts[index + 2]) else { continue }
                let category = texts[index + 2]
                let color: (Double, Double, Double)
                switch category {
                case "Work": color = (0.2980392157, 0.5019607843, 0.7294117647)
                case "Personal": color = (0.3215686275, 0.5372549020, 0.4078431373)
                default: color = (0.7411764706, 0.4431372549, 0.3294117647)
                }
                let calendar = CalendarSnapshot(calendarIdentifier: category, title: category, allowsContentModifications: true, red: color.0, green: color.1, blue: color.2)
                generated.append(EventSnapshot(eventIdentifier: "preview-\(index)", calendarItemIdentifier: "preview-\(index)", startDate: date, endDate: date.addingTimeInterval(3600), title: texts[index], isAllDay: false, isRecurring: false, calendar: calendar))
            }
            model.events = generated
            if FidelityPreview.name.hasSuffix("· all") { model.selected = Set(generated.map(\.stableID)) }
            else if FidelityPreview.name.hasSuffix("· partial"), let event = generated.first { model.selected = [event.stableID] }
            ready = true
            #endif
        }
    }
}

nonisolated struct EventSnapshot: Hashable, Sendable {
    let eventIdentifier: String?
    let calendarItemIdentifier: String
    let startDate: Date
    let endDate: Date
    let title: String?
    let isAllDay: Bool
    let isRecurring: Bool
    fileprivate let calendar: CalendarSnapshot
    var stableID: String { "\(eventIdentifier ?? calendarItemIdentifier)|\(startDate.timeIntervalSince1970)" }
}

// EKEventStore and all mutable EKEvent objects stay inside this actor.
// The UI receives value snapshots only, never EventKit objects from another executor.
private actor CalendarQueryWorker {
    private let store = EKEventStore()
    func fetch(start: Date, end: Date, future: Bool, now: Date) -> [EventSnapshot] {
        store.reset()
        var foundBySeries: [String: EventSnapshot] = [:]
        var cursor = start
        while cursor < end {
            let next = min(Calendar.current.date(byAdding: .year, value: 1, to: cursor)!, end)
            for event in store.events(matching: store.predicateForEvents(withStart: cursor, end: next, calendars: nil)) {
                // Exclude read-only calendars (subscriptions, holidays, read-only shared calendars)
                guard event.calendar.allowsContentModifications else { continue }
                guard future ? event.startDate >= now : event.endDate < now else { continue }
                let isRecurring = event.hasRecurrenceRules || event.isDetached
                let seriesKey = isRecurring ? "rec_\(event.calendarItemIdentifier)" : "single_\(event.eventIdentifier ?? event.calendarItemIdentifier)_\(event.startDate.timeIntervalSince1970)"

                let color = event.calendar.cgColor.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil)?.components ?? [0.2, 0.4, 1, 1]
                let calendar = CalendarSnapshot(calendarIdentifier: event.calendar.calendarIdentifier, title: event.calendar.title, allowsContentModifications: event.calendar.allowsContentModifications, red: color[0], green: color[1], blue: color[2])
                let snapshot = EventSnapshot(eventIdentifier: event.eventIdentifier, calendarItemIdentifier: event.calendarItemIdentifier, startDate: event.startDate, endDate: event.endDate, title: event.title, isAllDay: event.isAllDay, isRecurring: isRecurring, calendar: calendar)

                if let existing = foundBySeries[seriesKey] {
                    if future {
                        if snapshot.startDate < existing.startDate { foundBySeries[seriesKey] = snapshot }
                    } else {
                        if snapshot.startDate > existing.startDate { foundBySeries[seriesKey] = snapshot }
                    }
                } else {
                    foundBySeries[seriesKey] = snapshot
                }
            }
            cursor = next
        }
        return Array(foundBySeries.values)
    }
    func delete(_ targets: [EventSnapshot]) -> (deleted: Int, failures: [String], removed: Set<String>) {
        var deleted = 0
        var failures: [String] = []
        var removed: Set<String> = []
        for target in targets {
            do {
                guard EKEventStore.authorizationStatus(for: .event) == .fullAccess,
                      let calendar = store.calendar(withIdentifier: target.calendar.calendarIdentifier), calendar.allowsContentModifications,
                      let event = store.events(matching: store.predicateForEvents(withStart: target.startDate.addingTimeInterval(-1), end: target.startDate.addingTimeInterval(1), calendars: [calendar])).first(where: {
                          $0.calendarItemIdentifier == target.calendarItemIdentifier && $0.startDate == target.startDate
                      }) else {
                    failures.append("An event was changed, removed, or became read only.")
                    continue
                }
                let span: EKSpan = target.isRecurring ? .futureEvents : .thisEvent
                try store.remove(event, span: span, commit: false)
                removed.insert(target.stableID)
                deleted += 1
            } catch { failures.append(error.localizedDescription) }
        }
        if deleted > 0 {
            do { try store.commit() }
            catch { failures.append(error.localizedDescription) }
        }
        return (deleted, failures, removed)
    }
}

@MainActor @Observable final class CalendarStore {
    let store = EKEventStore()
    private let worker = CalendarQueryWorker()
    private var loadGeneration = 0
    var events: [EventSnapshot] = []
    var loading = false
    var working = false
    var preview = false
    var deletedCount = 0
    var allowed = false
    var error: String?
    var result: String?
    var selected: Set<String> = []
    var future = false
    var start = Date()
    var end = Date()
    func key(_ event: EventSnapshot) -> String { event.stableID }
    func load() async {
        guard !preview else { return }
        loadGeneration += 1
        let generation = loadGeneration
        loading = true
        error = nil
        defer { if generation == loadGeneration { loading = false } }
        do {
            if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
                allowed = try await store.requestFullAccessToEvents()
            } else { allowed = EKEventStore.authorizationStatus(for: .event) == .fullAccess }
            guard allowed else { events = []; selected.removeAll(); return }
            let now = Date()
            start = future ? now : Calendar.current.date(byAdding: .year, value: -5, to: now)!
            end = future ? Calendar.current.date(byAdding: .year, value: 5, to: now)! : now
            let fetched = await worker.fetch(start: start, end: end, future: future, now: now)
            guard generation == loadGeneration else { return }
            guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { allowed = false; events = []; selected.removeAll(); return }
            events = fetched
            selected.formIntersection(Set(events.filter { $0.calendar.allowsContentModifications }.map(key)))
        } catch { if generation == loadGeneration { events = []; selected.removeAll(); self.error = error.localizedDescription } }
    }
    func delete() async {
        guard !preview, !working else { return }
        deletedCount = 0
        working = true
        defer { working = false }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            allowed = false; events = []; selected.removeAll()
            error = "Calendar access is unavailable. Allow full access in Settings and try again."
            return
        }
        let targets = events.filter { selected.contains(key($0)) && $0.calendar.allowsContentModifications }
        let outcome = await worker.delete(targets)
        deletedCount = outcome.deleted
        selected.subtract(outcome.removed)
        result = "Deleted \(outcome.deleted) event\(outcome.deleted == 1 ? "" : "s")." + (outcome.failures.isEmpty ? "" : " \(outcome.failures.count) could not be deleted. \(outcome.failures[0])")
        await load()
        if !outcome.failures.isEmpty { error = result }
    }
}

