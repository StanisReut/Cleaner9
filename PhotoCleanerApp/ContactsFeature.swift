import SwiftUI
import Contacts
import Observation
import CryptoKit

struct ContactCheck: View {
    let selected: Bool
    var body: some View {
        Circle().fill(selected ? Color(hex: 0x1CB450) : Color(hex: 0xE2E8F2))
            .frame(width: 24, height: 24)
            .overlay { if selected { Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white) } }
            .accessibilityHidden(true)
    }
}

// CNContact instances are immutable snapshots and documented as thread-safe.
// Only immutable contacts cross this boundary; CNMutableContact and CNContactStore never do.
nonisolated private struct ContactSnapshotBatch: @unchecked Sendable {
    let contacts: [CNContact]
}

private struct ContactsOutcome: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// All contact routes share the real row, selection, footer and result components.
private struct ContactLayout<Content: View, Footer: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer
    var body: some View {
        VStack(spacing: 0) {
            CleanerHeader(title: title)
            content().frame(maxWidth: .infinity, maxHeight: .infinity)
            footer().padding(.horizontal, 16).padding(.vertical, 16)
        }.background(CleanerStyle.bg.ignoresSafeArea()).foregroundStyle(CleanerStyle.ink)
            .font(CleanerStyle.font(16)).toolbar(.hidden, for: .navigationBar)
    }
}

private struct ContactResultModifier: ViewModifier {
    @Binding var outcome: ContactsOutcome?
    func body(content: Content) -> some View {
        content.overlay {
            if let outcome {
                CleanerModal(title: outcome.title, message: outcome.message, asset: outcome.title.localizedCaseInsensitiveContains("restored") ? "RestoreSuccess" : "ContactsSuccess", onPrimary: { self.outcome = nil })
            }
        }
    }
}

private struct ContactSelection: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    let count: Int
    var noun = "contacts"
    let allSelected: Bool
    let action: () -> Void
    var body: some View {
        let layout = dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())
        layout {
            Text("\(count) \(noun)").foregroundStyle(CleanerStyle.secondary)
            if !dynamicType.isAccessibilitySize { Spacer() }
            Button(allSelected ? "Deselect all" : "Select all", action: action)
                .font(CleanerStyle.font(16, .semibold)).foregroundStyle(CleanerStyle.blue).padding(.vertical, 10).contentShape(Rectangle()).padding(.vertical, -10)
        }.frame(minHeight: 24)
    }
}

private func contactInitials(_ contact: CNContact) -> String {
    guard !contact.givenName.isEmpty || !contact.familyName.isEmpty else { return "#" }
    return [contact.givenName, contact.familyName].compactMap(\.first).map(String.init).joined().uppercased()
}

private func contactLetter(_ contact: CNContact) -> String {
    let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
    guard let first = name.first, first.isLetter else { return "#" }
    return String(first).uppercased()
}

private func contactSubtitle(_ contact: CNContact) -> String {
    if contact.givenName.isEmpty && contact.familyName.isEmpty { return "Missing name" }
    return contact.phoneNumbers.first?.value.stringValue ?? "Missing phone number"
}

private struct ContactRow: View {
    let contact: CNContact
    let name: String
    var selected: Bool? = nil
    var incomplete = false
    var body: some View {
        HStack(spacing: 8) {
            Text(contactInitials(contact)).lineLimit(1).minimumScaleFactor(0.4).font(CleanerStyle.font(16, .semibold))
                .foregroundStyle(CleanerStyle.blue).frame(width: 40, height: 40)
                .background(CleanerStyle.track, in: Circle()).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(name).font(CleanerStyle.font(16, .semibold)).frame(minHeight: 24).fixedSize(horizontal: false, vertical: true)
                Text(contactSubtitle(contact)).font(CleanerStyle.font(16)).frame(minHeight: 24).foregroundStyle(CleanerStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let selected {
                ContactCheck(selected: selected)
            }
        }.padding(.horizontal, 16).padding(.vertical, 8).frame(minHeight: incomplete ? 88 : 64)
            .background(.white, in: RoundedRectangle(cornerRadius: incomplete ? 16 : 8)).foregroundStyle(CleanerStyle.ink)
    }
}

private struct ContactEmpty: View {
    let title: String
    var message: String? = nil
    let asset: String
    var body: some View {
        VStack(spacing: 8) {
            Image(asset).resizable().scaledToFit().frame(maxWidth: 312).frame(height: 264).accessibilityHidden(true)
            Text(title).font(CleanerStyle.font(24, .semibold)).multilineTextAlignment(.center)
            if let message { Text(message).foregroundStyle(CleanerStyle.secondary).multilineTextAlignment(.center) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, 16)
    }
}

struct ContactsScreen: View {
    @State var model = CleanerContactsStore()
    @State private var outcome: ContactsOutcome?
    @Environment(\.scenePhase) private var scenePhase
    init(model: CleanerContactsStore? = nil, resultTitle: String? = nil, resultMessage: String = "") {
        _model = State(initialValue: model ?? CleanerContactsStore())
        _outcome = State(initialValue: resultTitle.map { ContactsOutcome(title: $0, message: resultMessage) })
    }
    var body: some View {
        CleanerPage(title: "Contacts") {
            if model.loading { ProgressView("Loading contacts…") }
            if model.allowed && !model.loading {
                NavigationLink { ContactListScreen(model: model, incomplete: false) } label: { hubRow("All contacts", icon: "book.closed", count: model.contacts.count) }
                NavigationLink { ContactDuplicatesScreen(model: model) } label: { hubRow("Duplicates", icon: "person.2", count: model.duplicates.reduce(0) { $0 + $1.count }) }
                NavigationLink { ContactListScreen(model: model, incomplete: true) } label: { hubRow("Incomplete", icon: "person.crop.circle.badge.questionmark", count: model.incomplete.count) }
            } else if !model.loading {
                EmptyState(title: "Allow contacts access", message: "Grant access to organize your contacts. With limited access, only shared contacts are shown.", systemImage: "person.crop.circle")
                Button("Open Settings", action: openCleanerSettings)
            }
            NavigationLink { ContactBackupsScreen(model: model) } label: { hubRow("Backups", icon: "archivebox", count: model.backups.count) }
            if let error = model.error { Text(error).foregroundStyle(.red); Button("Try again") { Task { await model.load() } } }
        }.task { await model.load() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.load() } } }
            .onChange(of: model.completionSerial) { _, _ in
                if model.completionDestination == "contacts" { outcome = ContactsOutcome(title: model.completionTitle, message: model.completionMessage) }
            }
            .modifier(ContactResultModifier(outcome: $outcome))
    }
    private func hubRow(_ title: String, icon: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(["book.closed": "ContactsAllIcon", "person.2": "ContactsDuplicateIcon", "person.crop.circle.badge.questionmark": "ContactsIncompleteIcon", "archivebox": "ContactsBackupIcon"][icon] ?? "ContactsAllIcon").resizable().scaledToFit().frame(width: 40, height: 40)
            Text(title).font(CleanerStyle.font(16, .semibold)); Spacer()
            Text("\(count)").foregroundStyle(CleanerStyle.blue)
            Disclosure()
        }.foregroundStyle(CleanerStyle.ink).frame(minHeight: 48).cleanerCard()
    }
}

private struct ContactListScreen: View {
    @Bindable var model: CleanerContactsStore
    let incomplete: Bool
    @State private var selected: Set<String>
    @State private var confirm = false
    @State private var outcome: ContactsOutcome?
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.dismiss) private var dismiss
    init(model: CleanerContactsStore, incomplete: Bool, selected: Set<String> = [], resultTitle: String? = nil, resultMessage: String = "") {
        self.model = model; self.incomplete = incomplete
        _selected = State(initialValue: selected)
        _outcome = State(initialValue: resultTitle.map { ContactsOutcome(title: $0, message: resultMessage) })
    }
    private var values: [CNContact] { incomplete ? model.incomplete.sorted { contactLetter($0) == "#" ? false : contactLetter($1) == "#" ? true : model.name($0) < model.name($1) } : model.contacts }
    private var letters: [String] { values.map(contactLetter).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } } }
    private var indexLetters: [String] { letters.filter { $0 != "#" }.sorted() + (letters.contains("#") ? ["#"] : []) }
    private var allSelected: Bool { !values.isEmpty && values.allSatisfy { selected.contains($0.identifier) } }
    private var deleteTitle: String { selected.isEmpty ? "Delete contacts" : "Delete \(selected.count) Contact\(selected.count == 1 ? "" : "s")" }
    var body: some View {
        ContactLayout(title: incomplete ? "Incomplete" : "All contacts") {
            if model.loading { ProgressView("Loading contacts…") }
            else if !model.allowed {
                VStack { EmptyState(title: "Allow contacts access", message: "Restore contacts access in Settings to continue.", systemImage: "person.crop.circle"); Button("Open Settings", action: openCleanerSettings) }
            } else if values.isEmpty {
                ContactEmpty(title: "No contacts", asset: "EmptyContacts")
            } else {
                VStack(spacing: 16) {
                    ContactSelection(count: values.count, allSelected: allSelected) {
                        selected = allSelected ? [] : Set(values.map(\.identifier))
                    }.disabled(model.working)
                    ScrollViewReader { proxy in
                        HStack(alignment: .top, spacing: 8) {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 8) {
                                    if incomplete {
                                        ForEach(values, id: \.identifier) { row($0) }
                                    } else {
                                        ForEach(letters, id: \.self) { letter in
                                            Text(letter).font(CleanerStyle.font(16, .semibold)).frame(minHeight: 24).id(letter)
                                            ForEach(values.filter { contactLetter($0) == letter }, id: \.identifier) { row($0) }
                                        }
                                    }
                                }
                            }
                            if !incomplete && !dynamicType.isAccessibilitySize {
                                GeometryReader { rail in
                                    let height = min(rail.size.height, indexLetters.count > 20 ? 548.0 : 320.0)
                                    let cellHeight: CGFloat = indexLetters.count > 20 ? 16 : 24
                                    VStack(spacing: 0) {
                                        ForEach(Array(indexLetters.enumerated()), id: \.element) { index, letter in
                                            if index > 0 { Spacer(minLength: 0) }
                                            Text(index % 2 == 0 || letter == "#" || letter == "Z" ? letter : "·")
                                                .font(CleanerStyle.font(16, .semibold)).frame(width: 16, height: cellHeight)
                                                .accessibilityLabel("Jump to \(letter)").accessibilityAddTraits(.isButton)
                                                .accessibilityAction { withAnimation { proxy.scrollTo(letter, anchor: .top) } }
                                        }
                                    }.foregroundStyle(CleanerStyle.blue).frame(width: 44, height: height)
                                        .contentShape(Rectangle())
                                        .gesture(DragGesture(minimumDistance: 0).onChanged { touch in
                                            // One broad scrub target avoids overlapping tiny letter buttons.
                                            guard !indexLetters.isEmpty else { return }
                                            let fraction = (touch.location.y - cellHeight / 2) / max(1, height - cellHeight)
                                            let index = min(indexLetters.count - 1, max(0, Int((fraction * Double(indexLetters.count - 1)).rounded())))
                                            proxy.scrollTo(indexLetters[index], anchor: .top)
                                        })
                                        .frame(width: 16)
                                        .frame(maxHeight: .infinity)
                                }.frame(width: 16)
                            }
                        }
                    }
                }.padding(.horizontal, 16).padding(.top, 16)
            }
            if let error = model.error { Text(error).foregroundStyle(.red).padding(.horizontal, 16) }
        } footer: {
            if model.allowed && !model.loading && !values.isEmpty {
                PrimaryButton(title: model.working ? "Deleting…" : deleteTitle, disabled: selected.isEmpty || model.working) { confirm = true }
            }
        }.confirmationDialog("Delete \(selected.count) contacts?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Delete contacts", role: .destructive) {
                Task {
                    let before = Set(model.contacts.map(\.identifier)); let targets = selected
                    await model.delete(targets)
                    let removed = before.subtracting(Set(model.contacts.map(\.identifier))).intersection(targets).count
                    selected.formIntersection(Set(model.contacts.map(\.identifier)))
                    if removed > 0 {
                        let message = incomplete ? (model.incomplete.isEmpty ? "No incomplete contacts remain." : "\(model.incomplete.count) incomplete contact\(model.incomplete.count == 1 ? " remains." : "s remain.")") : (model.contacts.isEmpty ? "Your contact list is now empty." : "\(model.contacts.count) contacts remain.")
                        let title = "\(removed) contact\(removed == 1 ? "" : "s") deleted"
                        if incomplete {
                            model.publishCompletion(title: title, message: message, destination: "contacts")
                            dismiss()
                        } else { outcome = ContactsOutcome(title: title, message: message) }
                    }
                }
            }
        } message: { Text("A local vCard backup is saved first. Protected notes and account-specific fields may not be recoverable. Contacts may also be removed from synced accounts.") }
            .modifier(ContactResultModifier(outcome: $outcome))
    }
    private func row(_ contact: CNContact) -> some View {
        Button { if selected.contains(contact.identifier) { selected.remove(contact.identifier) } else { selected.insert(contact.identifier) } } label: {
            ContactRow(contact: contact, name: model.name(contact), selected: selected.contains(contact.identifier), incomplete: incomplete)
        }.buttonStyle(.plain).disabled(model.working).accessibilityAddTraits(selected.contains(contact.identifier) ? .isSelected : [])
    }
}

private struct ContactDuplicatesScreen: View {
    @Bindable var model: CleanerContactsStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String>
    init(model: CleanerContactsStore, selected: Set<String>? = nil) {
        self.model = model
        _selected = State(initialValue: selected ?? Set(model.duplicates.flatMap { $0.map(\.identifier) }))
    }
    private var groups: [[CNContact]] { model.duplicates }
    private var chosen: [[CNContact]] { groups.map { $0.filter { selected.contains($0.identifier) } }.filter { $0.count > 1 } }
    private var allSelected: Bool { !groups.isEmpty && groups.flatMap { $0 }.allSatisfy { selected.contains($0.identifier) } }
    var body: some View {
        ContactLayout(title: "Duplicates") {
            VStack(spacing: 16) {
                ContactSelection(count: groups.count, noun: "groups", allSelected: allSelected) {
                    selected = allSelected ? [] : Set(groups.flatMap { $0.map(\.identifier) })
                }
                if groups.isEmpty { ContactEmpty(title: "No duplicates", asset: "EmptyContacts") }
                else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                                let selectedMembers = group.filter { selected.contains($0.identifier) }
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Group \(index + 1)").font(CleanerStyle.font(16, .semibold)).frame(minHeight: 24)
                                    ForEach(group, id: \.identifier) { contact in
                                        Button { if selected.contains(contact.identifier) { selected.remove(contact.identifier) } else { selected.insert(contact.identifier) } } label: {
                                            HStack(spacing: 8) {
                                                VStack(alignment: .leading, spacing: 0) {
                                                    Text(model.name(contact)).font(CleanerStyle.font(16, .semibold))
                                                    Text(contact.phoneNumbers.first?.value.stringValue ?? "").foregroundStyle(CleanerStyle.secondary)
                                                }.frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 48)
                                                ContactCheck(selected: selected.contains(contact.identifier))
                                            }.foregroundStyle(CleanerStyle.ink)
                                        }.buttonStyle(.plain)
                                    }
                                    NavigationLink { ContactMergePreview(model: model, groups: [selectedMembers]) } label: { Text("Merge").font(CleanerStyle.font(16, .semibold)).foregroundStyle(selectedMembers.count > 1 ? CleanerStyle.blue : CleanerStyle.secondary).frame(minHeight: 24) }.disabled(selectedMembers.count < 2).buttonStyle(CleanerButtonStyle())
                                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 16))
                            }
                        }
                    }
                }
            }.padding(.horizontal, 16).padding(.top, 16).disabled(model.working)
        } footer: {
            if !groups.isEmpty {
                NavigationLink { ContactMergePreview(model: model, groups: chosen) } label: {
                    Text(chosen.isEmpty ? "Merge groups" : "Merge \(chosen.count) Group\(chosen.count == 1 ? "" : "s")")
                        .font(CleanerStyle.font(16, .semibold)).frame(maxWidth: .infinity, minHeight: 56)
                        .background(chosen.isEmpty ? Color(hex: 0xDFE6F0) : CleanerStyle.blue, in: RoundedRectangle(cornerRadius: 16))
                        .foregroundStyle(chosen.isEmpty ? CleanerStyle.secondary : .white)
                }.disabled(chosen.isEmpty).buttonStyle(CleanerButtonStyle())
            }
        }.onChange(of: model.completionSerial) { _, _ in
            if model.completionDestination == "contacts" { dismiss() }
        }
    }
}

private struct ContactMergePreview: View {
    @Bindable var model: CleanerContactsStore
    @Environment(\.dismiss) private var dismiss
    let groups: [[CNContact]]
    @State private var confirm = false
    @State private var outcome: ContactsOutcome?
    /// Displays every unique field intended for consolidation even when a conflict blocks saving.
    private func values(_ group: [CNContact], field: String) -> [String] {
        var result: [String] = []
        for contact in group {
            let candidates: [String]
            switch field {
            case "Mobile": candidates = contact.phoneNumbers.filter { $0.label != CNLabelWork }.map { $0.value.stringValue }
            case "Work": candidates = contact.phoneNumbers.filter { $0.label == CNLabelWork }.map { $0.value.stringValue }
            case "Email": candidates = contact.emailAddresses.map { $0.value as String }
            case "Company": candidates = [contact.organizationName].filter { !$0.isEmpty }
            case "Address": candidates = contact.postalAddresses.map { CNPostalAddressFormatter.string(from: $0.value, style: .mailingAddress) }
            case "Website": candidates = contact.urlAddresses.map { $0.value as String }
            case "Date": candidates = contact.dates.compactMap { Calendar.current.date(from: $0.value as DateComponents)?.formatted(date: .abbreviated, time: .omitted) }
            case "Social": candidates = contact.socialProfiles.map { [$0.value.service, $0.value.username, $0.value.urlString].filter { !$0.isEmpty }.joined(separator: " · ") }
            case "Relation": candidates = contact.contactRelations.map { $0.value.name }
            default: candidates = contact.instantMessageAddresses.map { "\($0.value.service) · \($0.value.username)" }
            }
            for value in candidates where !result.contains(value) { result.append(value) }
        }
        return result
    }
    private var previewError: String? {
        guard !model.preview else { return nil }
        do { for group in groups { _ = try model.mergedPreview(group) }; return nil } catch { return error.localizedDescription }
    }
    var body: some View {
        ContactLayout(title: "Merge preview") {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                        if let contact = group.first {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Text(contactInitials(contact)).lineLimit(1).minimumScaleFactor(0.4).foregroundStyle(CleanerStyle.blue).frame(width: 40, height: 40).background(CleanerStyle.track, in: Circle())
                                    VStack(alignment: .leading, spacing: 0) { Text(model.name(contact)).font(CleanerStyle.font(16, .semibold)); Text("Merged contact").foregroundStyle(CleanerStyle.secondary) }.frame(minHeight: 48)
                                }
                                ForEach(["Mobile", "Work", "Email", "Company", "Address", "Website", "Date", "Social", "Relation", "Message"], id: \.self) { field in
                                    let entries = values(group, field: field)
                                    if !entries.isEmpty {
                                        VStack(alignment: .leading, spacing: 0) {
                                            Text(field).foregroundStyle(CleanerStyle.secondary).frame(minHeight: 24)
                                            ForEach(entries, id: \.self) { Text($0).font(CleanerStyle.font(16, .semibold)).frame(minHeight: 24).textSelection(.enabled) }
                                        }.frame(minHeight: 48, alignment: .leading)
                                    }
                                }
                            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    if let previewError { Text(previewError).foregroundStyle(.red) }
                    if let error = model.error { Text(error).foregroundStyle(.red) }
                }.padding(.horizontal, 16).padding(.top, 16)
            }
        } footer: {
            PrimaryButton(title: model.working ? "Combining…" : groups.count > 1 ? "Merge \(groups.count) Groups" : "Merge", disabled: groups.isEmpty || model.working || previewError != nil) { confirm = true }
        }.confirmationDialog("Combine details and keep originals?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Combine and keep originals") {
                Task {
                    var combined = 0
                    for group in groups {
                        await model.mergeKeepingOriginals(group)
                        if model.error != nil { break }
                        combined += 1
                    }
                    if combined > 0 {
                        model.publishCompletion(title: "Contact details combined", message: "Details from \(combined) group\(combined == 1 ? "" : "s") were combined. Original contacts were retained and a backup was saved.", destination: "contacts")
                        dismiss()
                    }
                }
            }
        } message: { Text("Updates the first contact with unique details and saves a backup. Original contacts remain to protect notes and account-specific fields. No contacts are deleted.") }
            .modifier(ContactResultModifier(outcome: $outcome))
    }
}

private struct ContactBackupRecord {
    let url: URL
    let date: Date
    let contacts: [CNContact]
    var previewDateText: String? = nil
    var dateText: String { previewDateText ?? (date.formatted(.dateTime.month(.abbreviated).day().year()) + " · " + date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))) }
}

private struct ContactBackupsScreen: View {
    @Bindable var model: CleanerContactsStore
    var injectedRecords: [ContactBackupRecord]? = nil
    @State private var records: [ContactBackupRecord] = []
    @State private var outcome: ContactsOutcome?
    init(model: CleanerContactsStore, records: [ContactBackupRecord]? = nil, resultTitle: String? = nil, resultMessage: String = "") {
        self.model = model; self.injectedRecords = records
        _outcome = State(initialValue: resultTitle.map { ContactsOutcome(title: $0, message: resultMessage) })
    }
    private var shown: [ContactBackupRecord] { injectedRecords ?? records }
    var body: some View {
        ContactLayout(title: "Backups") {
            if shown.isEmpty {
                ContactEmpty(title: "No backups yet", message: "Save a copy of your contacts before making changes.", asset: "EmptyBackups")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(shown, id: \.url) { record in
                            NavigationLink { ContactBackupDetail(model: model, record: record) } label: {
                                HStack(spacing: 8) {
                                    Image("ContactsBackupIcon").resizable().scaledToFit().frame(width: 40, height: 40)
                                    VStack(alignment: .leading, spacing: 0) { Text(record.dateText).font(CleanerStyle.font(16, .semibold)); Text("\(record.contacts.count) contacts").foregroundStyle(CleanerStyle.secondary) }.frame(maxWidth: .infinity, alignment: .leading)
                                    Disclosure()
                                }.padding(16).frame(minHeight: 96).background(.white, in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(CleanerStyle.ink)
                            }
                        }
                    }.padding(.horizontal, 16).padding(.top, 16)
                }
            }
            if let error = model.error { Text(error).foregroundStyle(.red).padding(.horizontal, 16) }
        } footer: {
            PrimaryButton(title: model.working ? "Creating backup…" : "Create backup", disabled: !model.allowed || model.contacts.isEmpty || model.working) {
                Task { await model.createBackup(); refresh() }
            }
        }.task { refresh() }.onChange(of: model.backups) { _, _ in refresh() }
            .onChange(of: model.completionSerial) { _, _ in
                if model.completionDestination == "backups" { outcome = ContactsOutcome(title: model.completionTitle, message: model.completionMessage) }
            }
            .modifier(ContactResultModifier(outcome: $outcome))
    }
    private func refresh() {
        guard !model.preview else { return }
        var loaded: [ContactBackupRecord] = []
        for url in model.backups {
            do {
                let values = try CNContactVCardSerialization.contacts(with: Data(contentsOf: url))
                let date = (try url.resourceValues(forKeys: [.creationDateKey])).creationDate ?? .distantPast
                loaded.append(ContactBackupRecord(url: url, date: date, contacts: values))
            } catch { model.error = "Couldn’t read a backup: \(error.localizedDescription)" }
        }
        records = loaded.sorted { $0.date > $1.date }
    }
}

private struct ContactBackupDetail: View {
    @Bindable var model: CleanerContactsStore
    @Environment(\.dismiss) private var dismiss
    let record: ContactBackupRecord
    @State private var confirm = false
    @State private var restoring = false
    @State private var outcome: ContactsOutcome?
    var body: some View {
        ContactLayout(title: "Contact backup") {
            VStack(alignment: .leading, spacing: 16) {
                Text(record.dateText).font(CleanerStyle.font(16, .semibold)).frame(minHeight: 24)
                Text("\(record.contacts.count) contacts").frame(minHeight: 24)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(record.contacts.enumerated()), id: \.element.identifier) { index, contact in
                            ContactRow(contact: contact, name: model.name(contact)).overlay(alignment: .bottom) {
                                if index < record.contacts.count - 1 { Rectangle().fill(CleanerStyle.track).frame(height: 1).padding(.horizontal, 16) }
                            }
                        }
                    }.background(.white, in: RoundedRectangle(cornerRadius: 16)).clipShape(RoundedRectangle(cornerRadius: 16))
                }
                if let error = model.error { Text(error).foregroundStyle(.red) }
            }.padding(.horizontal, 16).padding(.top, 16)
        } footer: {
            PrimaryButton(title: "Restore", disabled: record.contacts.isEmpty || !model.allowed || model.working) { confirm = true }
        }.confirmationDialog("Restore this backup?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Restore contacts") { restoring = true }
            ShareLink(item: record.url) { Text("Export vCard") }
        } message: { Text("Adds missing contacts without replacing existing ones. Previously restored entries are skipped. Backups are stored on this device and may not include protected notes.") }
            .fullScreenCover(isPresented: $restoring) {
                ContactRestoreScreen(model: model, record: record) { completed in
                    restoring = false
                    if completed {
                        model.publishCompletion(title: "\(model.restoreAddedCount) contact\(model.restoreAddedCount == 1 ? "" : "s") restored", message: model.notice ?? "Your backup has been restored.", destination: "backups")
                        dismiss()
                    }
                }
            }.modifier(ContactResultModifier(outcome: $outcome))
    }
}

private struct ContactRestoreScreen: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Bindable var model: CleanerContactsStore
    let record: ContactBackupRecord
    var finished: (Bool) -> Void = { _ in }
    private var total: Int { model.preview ? record.contacts.count : model.restoreTotal }
    private var current: Int { model.preview ? record.contacts.count / 2 : model.restoredCount }
    private var progress: Double { total > 0 ? Double(current) / Double(total) : 0 }
    private var illustrationContacts: [CNContact] {
        if model.preview { return ["Alex Carter", "Chloe Park", "Ella Brooks", "Noah Scott"].compactMap { name in record.contacts.first { model.name($0) == name } } }
        return Array(record.contacts.prefix(4))
    }
    var body: some View {
        ContactLayout(title: "Restore contacts") {
            if dynamicType.isAccessibilitySize { ScrollView { restoreContent.padding(.vertical, 16) } }
            else { restoreContent.frame(maxWidth: .infinity, maxHeight: .infinity) }
        } footer: {
            PrimaryButton(title: "Cancel") { model.restoreCancelled = true; if model.preview { finished(false) } }
        }.task {
            guard !model.preview else { return }
            await model.restore(record.url)
            finished(!model.restoreCancelled && model.error == nil)
        }
    }
    private var restoreContent: some View {
            VStack(spacing: 24) {
                ZStack {
                    ForEach(Array(illustrationContacts.enumerated()), id: \.offset) { index, contact in
                        let widths: [CGFloat] = [128, 128, 136, 136]
                        let heights: [CGFloat] = [168, 144, 144, 160]
                        let colors: [UInt32] = [0xE1EAF7, 0xE5EEEA, 0xF1E8DF, 0xEBE7F2]
                        let x: [CGFloat] = [-79.9323, 84.3567, -91.6822, 84.4721]
                        let y: [CGFloat] = [-75.7246, -67.7936, 83.7631, 75.7577]
                        VStack(spacing: 8) {
                            Text(contactInitials(contact)).lineLimit(1).minimumScaleFactor(0.4).font(CleanerStyle.font(16, .semibold)).foregroundStyle(Color(hex: 0x446B9A)).frame(width: 40, height: 40).background(.white, in: Circle())
                            Text(contact.givenName).font(CleanerStyle.font(16, .semibold)).foregroundStyle(Color(hex: 0x446B9A)).frame(height: 24)
                            Spacer(minLength: 0)
                        }.padding(.top, index == 2 ? 56 : index == 3 ? 72 : 16).frame(width: widths[index]-16, height: heights[index]-16).background(Color(hex: colors[index]), in: RoundedRectangle(cornerRadius: 16)).padding(8).background(.white, in: RoundedRectangle(cornerRadius: 24))
                            .compositingGroup().shadow(color: Color(hex: 0x1C2B52).opacity(0.18), radius: 8, y: 8)
                            .rotationEffect(.degrees(index == 0 || index == 3 ? -8 : 8)).offset(x: x[index], y: y[index])
                    }
                    ZStack {
                        Circle().fill(.white).frame(width: 200, height: 200).shadow(color: Color(hex: 0x1A264D).opacity(0.2), radius: 8, y: 8)
                        Circle().stroke(Color(hex: 0xE6ECF7), lineWidth: 16).frame(width: 176, height: 176)
                        Circle().trim(from: 0, to: progress).stroke(CleanerStyle.blue, style: StrokeStyle(lineWidth: 24, lineCap: .round)).rotationEffect(.degrees(-90)).frame(width: 176, height: 176)
                        Text("\(Int(progress * 100))%").font(CleanerStyle.font(40, .bold))
                    }.offset(y: 4)
                }.dynamicTypeSize(...DynamicTypeSize.large).frame(maxWidth: 328).frame(height: 344).accessibilityElement(children: .ignore).accessibilityLabel("\(Int(progress * 100)) percent restored")
                VStack(spacing: 0) { Text("Restoring contacts…").font(CleanerStyle.font(16, .semibold)); Text("\(current) of \(total) contacts").foregroundStyle(CleanerStyle.secondary) }
            }.multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
    }
}

@MainActor @Observable final class CleanerContactsStore {
    var completionSerial = 0
    var completionTitle = ""
    var completionMessage = ""
    var completionDestination = ""
    func publishCompletion(title: String, message: String, destination: String) {
        completionTitle = title; completionMessage = message; completionDestination = destination
        completionSerial += 1
    }
    let store = CNContactStore()
    var contacts: [CNContact] = []
    var backups: [URL] = []
    var loading = false
    var working = false
    var preview = false
    var restoredCount = 0
    var restoreAddedCount = 0
    var restoreTotal = 0
    var restoreCancelled = false
    private var loadGeneration = 0
    var allowed = false
    var error: String?
    var notice: String?
    var keys: [CNKeyDescriptor] { [CNContactVCardSerialization.descriptorForRequiredKeys(), CNContactFormatter.descriptorForRequiredKeys(for: .fullName)] }
    func requireAccess() throws {
        guard !preview else { return }
        let status = CNContactStore.authorizationStatus(for: .contacts)
        allowed = status == .authorized || status.rawValue == 4
        guard allowed else {
            contacts = []
            throw NSError(domain: "Contacts", code: 3, userInfo: [NSLocalizedDescriptionKey: "Contacts access is unavailable. Allow access in Settings and try again."])
        }
    }
    private func fetchContacts(identifiers: [String]? = nil) async throws -> [CNContact] {
        try requireAccess()
        let batch = try await Task.detached(priority: .userInitiated) {
            let reader = CNContactStore()
            let keys: [CNKeyDescriptor] = [CNContactVCardSerialization.descriptorForRequiredKeys(), CNContactFormatter.descriptorForRequiredKeys(for: .fullName)]
            if let identifiers {
                return ContactSnapshotBatch(contacts: try identifiers.map { try reader.unifiedContact(withIdentifier: $0, keysToFetch: keys) })
            }
            var fetched: [CNContact] = []
            let request = CNContactFetchRequest(keysToFetch: keys)
            request.sortOrder = .userDefault
            try reader.enumerateContacts(with: request) { contact, _ in fetched.append(contact) }
            return ContactSnapshotBatch(contacts: fetched.sorted {
                let first = CNContactFormatter.string(from: $0, style: .fullName) ?? $0.phoneNumbers.first?.value.stringValue ?? "Unnamed contact"
                let second = CNContactFormatter.string(from: $1, style: .fullName) ?? $1.phoneNumbers.first?.value.stringValue ?? "Unnamed contact"
                return first.localizedCaseInsensitiveCompare(second) == .orderedAscending
            })
        }.value
        try requireAccess()
        return batch.contacts
    }
    func name(_ contact: CNContact) -> String { CNContactFormatter.string(from: contact, style: .fullName) ?? contact.phoneNumbers.first?.value.stringValue ?? "Unnamed contact" }
    func phone(_ value: String) -> String { value.filter(\.isNumber) }
    var duplicates: [[CNContact]] {
        let numbers = contacts.map { Set($0.phoneNumbers.map { phone($0.value.stringValue) }.filter { !$0.isEmpty }) }
        var owners: [String: [Int]] = [:]
        for index in contacts.indices {
            for number in numbers[index] { owners[number, default: []].append(index) }
        }
        var visited: Set<Int> = []
        var visitedNumbers: Set<String> = []
        var groups: [[CNContact]] = []
        for index in contacts.indices where !visited.contains(index) && !numbers[index].isEmpty {
            var pending = [index]
            visited.insert(index)
            var group: [CNContact] = []
            while let current = pending.popLast() {
                group.append(contacts[current])
                for number in numbers[current] where visitedNumbers.insert(number).inserted {
                    for neighbor in owners[number, default: []] where visited.insert(neighbor).inserted { pending.append(neighbor) }
                }
            }
            if group.count > 1 { groups.append(group) }
        }
        return groups
    }
    var incomplete: [CNContact] { contacts.filter { ($0.givenName.isEmpty && $0.familyName.isEmpty) || $0.phoneNumbers.isEmpty } }
    func directory() throws -> URL {
        let url = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("ContactBackups", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func load() async {
        guard !preview else { return }
        loadGeneration += 1
        let generation = loadGeneration
        loading = true; error = nil
        defer { if generation == loadGeneration { loading = false } }
        do {
            let status = CNContactStore.authorizationStatus(for: .contacts)
            if status == .notDetermined { allowed = try await store.requestAccess(for: .contacts) }
            else { allowed = status == .authorized || status.rawValue == 4 }
            backups = try FileManager.default.contentsOfDirectory(at: directory(), includingPropertiesForKeys: nil).filter { $0.pathExtension == "vcf" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
            guard allowed else { contacts = []; return }
            let fetched = try await fetchContacts()
            guard generation == loadGeneration else { return }
            contacts = fetched
        } catch { if generation == loadGeneration { contacts = []; self.error = error.localizedDescription } }
    }
    @discardableResult func backup(_ values: [CNContact]) throws -> URL {
        guard !preview else { return URL(fileURLWithPath: "/preview.vcf") }
        let data = try CNContactVCardSerialization.data(with: values)
        let file = try directory().appendingPathComponent("Contacts-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(6)).vcf")
        try data.write(to: file, options: .atomic)
        backups.insert(file, at: 0)
        return file
    }
    func createBackup() async {
        guard !preview, !working else { return }
        working = true
        defer { working = false }
        notice = nil; error = nil
        do { contacts = try await fetchContacts(); _ = try backup(contacts); notice = "Backed up \(contacts.count) contacts on this device. Protected notes and account-specific fields are not guaranteed to be included." } catch { self.error = error.localizedDescription }
    }
    func mergedPreview(_ values: [CNContact]) throws -> CNMutableContact {
        guard let first = values.first else { throw NSError(domain: "Contacts", code: 1, userInfo: [NSLocalizedDescriptionKey: "No contacts selected."]) }
        let result = first.mutableCopy() as! CNMutableContact
        // Scalar conflicts require a human choice; never silently choose one person's identity.
        let scalarKeys = [CNContactNamePrefixKey, CNContactGivenNameKey, CNContactMiddleNameKey, CNContactFamilyNameKey, CNContactPreviousFamilyNameKey, CNContactNameSuffixKey, CNContactNicknameKey, CNContactPhoneticGivenNameKey, CNContactPhoneticMiddleNameKey, CNContactPhoneticFamilyNameKey, CNContactOrganizationNameKey, CNContactDepartmentNameKey, CNContactJobTitleKey, CNContactBirthdayKey, CNContactNonGregorianBirthdayKey, CNContactImageDataKey]
        for key in scalarKeys {
            let populated = values.filter { $0.isKeyAvailable(key) }.compactMap { $0.value(forKey: key) as? NSObject }.filter { !(($0 as? String)?.isEmpty ?? false) }
            guard let value = populated.first else { continue }
            guard populated.allSatisfy({ $0.isEqual(value) }) else { throw NSError(domain: "Contacts", code: 2, userInfo: [NSLocalizedDescriptionKey: "These contacts have conflicting \(key). Review them in Contacts before combining."]) }
            result.setValue(value, forKey: key)
        }
        result.phoneNumbers = union(values.flatMap(\.phoneNumbers))
        result.emailAddresses = union(values.flatMap(\.emailAddresses))
        result.postalAddresses = union(values.flatMap(\.postalAddresses))
        result.urlAddresses = union(values.flatMap(\.urlAddresses))
        result.dates = union(values.flatMap(\.dates))
        result.contactRelations = union(values.flatMap(\.contactRelations))
        result.socialProfiles = union(values.flatMap(\.socialProfiles))
        result.instantMessageAddresses = union(values.flatMap(\.instantMessageAddresses))
        return result
    }
    private func union<T>(_ values: [CNLabeledValue<T>]) -> [CNLabeledValue<T>] where T: NSCopying, T: NSSecureCoding {
        var result: [CNLabeledValue<T>] = []
        for item in values {
            if !result.contains(where: { $0.label == item.label && ($0.value as! NSObject).isEqual(item.value) }) { result.append(item) }
        }
        return result
    }
    func mergeKeepingOriginals(_ values: [CNContact]) async {
        guard !preview, !working else { return }
        working = true
        defer { working = false }
        notice = nil; error = nil
        do {
            try requireAccess()
            let current = try await fetchContacts(identifiers: values.map(\.identifier))
            let merged = try mergedPreview(current)
            _ = try backup(current)
            let request = CNSaveRequest()
            request.update(merged)
            try store.execute(request)
            await load()
            notice = "Combined details into \(name(merged)). All original contacts were retained to protect notes and account-specific fields. A backup was saved first."
        } catch { self.error = error.localizedDescription }
    }
    func delete(_ identifiers: Set<String>) async {
        guard !preview, !working else { return }
        working = true
        defer { working = false }
        notice = nil; error = nil
        do {
            try requireAccess()
            let chosen = try await fetchContacts(identifiers: Array(identifiers))
            guard !chosen.isEmpty else { return }
            _ = try backup(chosen)
            let request = CNSaveRequest()
            for contact in chosen { request.delete(contact.mutableCopy() as! CNMutableContact) }
            try store.execute(request)
            notice = "Deleted \(chosen.count) contacts. A vCard backup was saved first; protected notes and account-specific fields may not be recoverable."
            await load()
        } catch { self.error = error.localizedDescription }
    }
    func fingerprint(_ contact: CNContact) throws -> String {
        let data = try CNContactVCardSerialization.data(with: [contact])
        let text = String(decoding: data, as: UTF8.self).components(separatedBy: .newlines).filter { !$0.hasPrefix("UID:") && !$0.hasPrefix("REV:") && !$0.isEmpty }.joined(separator: "\n")
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func restore(_ url: URL) async {
        guard !preview, !working else { return }
        working = true
        defer { working = false }
        notice = nil; error = nil
        var restored = 0
        restoredCount = 0; restoreAddedCount = 0; restoreTotal = 0; restoreCancelled = false
        do {
            contacts = try await fetchContacts()
            let values = try CNContactVCardSerialization.contacts(with: Data(contentsOf: url))
            restoreTotal = values.count
            var known = Set(try contacts.map(fingerprint))
            let receiptURL = url.appendingPathExtension("restored.json")
            var receipt: [String: String] = [:]
            if let data = try? Data(contentsOf: receiptURL), let saved = try? JSONDecoder().decode([String: String].self, from: data) {
                let existingIDs = Set(contacts.map(\.identifier))
                receipt = saved.filter { existingIDs.contains($0.value) }
                known.formUnion(receipt.keys)
            }
            for contact in values {
                await Task.yield()
                if restoreCancelled { break }
                restoredCount += 1
                let hash = try fingerprint(contact)
                guard !known.contains(hash) else { continue }
                let request = CNSaveRequest()
                let restoredContact = contact.mutableCopy() as! CNMutableContact
                request.add(restoredContact, toContainerWithIdentifier: nil)
                try store.execute(request)
                known.insert(hash); restored += 1; restoreAddedCount = restored
                receipt[hash] = restoredContact.identifier
                try JSONEncoder().encode(receipt).write(to: receiptURL, options: .atomic)
            }
            notice = restoreCancelled ? "Restore cancelled. \(restored) contacts were added; existing contacts were kept." : "Restored \(restored) contacts. Existing contacts were kept; previously restored entries were skipped."
            await load()
        } catch {
            let message = "Restored \(restored) contacts before restore stopped: \(error.localizedDescription). Those contacts remain saved."
            await load()
            self.error = message
        }
    }
}


#if DEBUG
private enum ContactsFixtures {
    static let standard: [(String, String)] = [
        ("", "+1 202 555 0119"),
        ("Alex C.", "+1 202 555 0101"),
        ("Alex Carter", "+1 202 555 0101"),
        ("Ben Morris", "+1 202 555 0102"),
        ("Benjamin Morris", "+1 202 555 0102"),
        ("Chloe P.", "+1 202 555 0103"),
        ("Chloe Park", "+1 202 555 0103"),
        ("Dan Lee", "+1 202 555 0104"),
        ("Daniel Lee", "+1 202 555 0104"),
        ("Ella B.", "+1 202 555 0105"),
        ("Ella Brooks", "+1 202 555 0105"),
        ("Harper Reed", ""),
        ("Jules Martin", "+1 202 555 0114"),
        ("Maya Green", ""),
        ("Noah S.", "+1 202 555 0106"),
        ("Noah Scott", "+1 202 555 0106"),
    ]
    static let alphabet: [(String, String)] = [
        ("Avery Stone", "+1 202 555 0120"),
        ("Ben Morris", "+1 202 555 0121"),
        ("Chloe Park", "+1 202 555 0122"),
        ("Daniel Lee", "+1 202 555 0123"),
        ("Ella Brooks", "+1 202 555 0124"),
        ("Finn Doyle", "+1 202 555 0125"),
        ("Grace Miller", "+1 202 555 0126"),
        ("Harper Reed", "+1 202 555 0127"),
        ("Iris Shaw", "+1 202 555 0128"),
        ("Jules Martin", "+1 202 555 0129"),
        ("Kai Evans", "+1 202 555 0130"),
        ("Lena Fox", "+1 202 555 0131"),
        ("Maya Green", "+1 202 555 0132"),
        ("Noah Scott", "+1 202 555 0133"),
        ("Olive Lane", "+1 202 555 0134"),
        ("Parker West", "+1 202 555 0135"),
        ("Quinn Baker", "+1 202 555 0136"),
        ("Riley Hall", "+1 202 555 0137"),
        ("Sofia King", "+1 202 555 0138"),
        ("Theo Mason", "+1 202 555 0139"),
        ("Uma Gray", "+1 202 555 0140"),
        ("Vera Young", "+1 202 555 0141"),
        ("Will Carter", "+1 202 555 0142"),
        ("Xavier Bell", "+1 202 555 0143"),
        ("Yara Hayes", "+1 202 555 0144"),
        ("Zoe Ross", "+1 202 555 0145"),
        ("", "+1 202 555 0119"),
    ]
    static func contact(_ name: String, _ phone: String) -> CNContact {
        let contact = CNMutableContact()
        let parts = name.split(separator: " ", maxSplits: 1).map(String.init)
        contact.givenName = parts.first ?? ""; contact.familyName = parts.count > 1 ? parts[1] : ""
        if !phone.isEmpty { contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: phone))] }
        return contact
    }
    static func mergeGroups() -> [[CNContact]] {
        let names = [("Alex Carter", "Alex C.", "alex", "North Studio"), ("Ben Morris", "Benjamin Morris", "ben", "Fieldwork"), ("Chloe Park", "Chloe P.", "chloe", "Studio Park"), ("Daniel Lee", "Dan Lee", "dan", "North Studio"), ("Ella Brooks", "Ella B.", "ella", "Fieldwork"), ("Noah Scott", "Noah S.", "noah", "Studio Park")]
        return names.enumerated().map { index, item in
            let first = contact(item.0, "+1 202 555 010\(index + 1)").mutableCopy() as! CNMutableContact
            first.organizationName = item.3
            let second = contact(item.1, "+1 202 555 010\(index + 1)").mutableCopy() as! CNMutableContact
            second.phoneNumbers.append(CNLabeledValue(label: CNLabelWork, value: CNPhoneNumber(stringValue: "+1 202 555 020\(index + 1)")))
            second.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: "\(item.2)@example.com" as NSString)]
            return [first, second]
        }
    }
}
#endif

struct ContactsFidelityScreen: View {
    @State private var model = CleanerContactsStore()
    @State private var ready = false
    private var key: String { FidelityPreview.name.components(separatedBy: " / ").last ?? "" }
    private var result: (String?, String) {
        let texts = FidelityPreview.texts
        guard texts.last == "Continue", texts.count >= 3 else { return (nil, "") }
        return (texts[texts.count - 3], texts[texts.count - 2])
    }
    private var records: [ContactBackupRecord] {
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 12, minute: key == "detail2" || key == "restore2" ? 28 : 24)) ?? .distantPast
        let first = ContactBackupRecord(url: URL(fileURLWithPath: "/preview-backup.vcf"), date: date, contacts: model.contacts, previewDateText: key == "detail2" || key == "restore2" ? "Nov 5, 2026 · 12:28" : "Nov 5, 2026 · 12:24")
        if key == "backups2" { return [ContactBackupRecord(url: URL(fileURLWithPath: "/preview-backup-2.vcf"), date: date.addingTimeInterval(240), contacts: model.contacts, previewDateText: "Nov 5, 2026 · 12:28"), first] }
        return [first]
    }
    var body: some View {
        Group {
            if ready {
                if key.hasPrefix("hub") || key.hasPrefix("incDone") || key.hasPrefix("merge") {
                    ContactsScreen(model: model, resultTitle: result.0, resultMessage: result.1)
                } else if key.hasPrefix("dup") {
                    ContactDuplicatesScreen(model: model, selected: key == "dupNone" ? [] : nil)
                } else if key.hasPrefix("preview") {
                    #if DEBUG
                    let groups = ContactsFixtures.mergeGroups()
                    ContactMergePreview(model: model, groups: key == "previewAll" ? groups : [groups[Int(key.replacingOccurrences(of: "preview", with: "")) ?? 0]])
                    #endif
                } else if key == "restore" || key == "restore2" {
                    ContactRestoreScreen(model: model, record: records[0])
                } else if key == "detail" || key == "detail2" {
                    ContactBackupDetail(model: model, record: records[0])
                } else if key == "empty" || key.hasPrefix("backups") || key == "restored" {
                    ContactBackupsScreen(model: model, records: key == "empty" ? [] : records, resultTitle: result.0, resultMessage: result.1)
                } else {
                    ContactListScreen(model: model, incomplete: key.hasPrefix("inc"), selected: initialSelection, resultTitle: result.0, resultMessage: result.1)
                }
            } else { Color.clear }
        }.task {
            guard FidelityPreview.active, !ready else { return }
            #if DEBUG
            model.preview = true; model.allowed = true
            let fixture = key.contains("A–Z") ? ContactsFixtures.alphabet : ContactsFixtures.standard
            model.contacts = fixture.map { ContactsFixtures.contact($0.0, $0.1) }
            if key.hasPrefix("dup") { model.contacts = ContactsFixtures.mergeGroups().flatMap { $0 } }
            if key == "allDone" || key == "allEmpty" || key == "A–Z · Deleted" { model.contacts = [] }
            if key == "hubSaved" { model.backups = [URL(fileURLWithPath: "/preview.vcf")] }
            ready = true
            #endif
        }
    }
    private var initialSelection: Set<String> {
        if key == "all1" || key.contains("· selected") { return Set(model.contacts.map(\.identifier)) }
        guard key.hasPrefix("inc"), let mask = Int(key.dropFirst(3)) else { return [] }
        let ordered = model.incomplete.sorted { contactLetter($0) == "#" ? false : contactLetter($1) == "#" ? true : model.name($0) < model.name($1) }
        return Set(ordered.enumerated().filter { mask & (1 << $0.offset) != 0 }.map { $0.element.identifier })
    }
}
