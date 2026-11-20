import Foundation
import Contacts
import EventKit

@MainActor
final class TestDataSeeder {
    static let shared = TestDataSeeder()
    private init() {}

    func seedAll() async throws -> (contactsCreated: Int, eventsCreated: Int) {
        let contacts = try await seedContacts()
        let events = try await seedCalendarEvents()
        return (contacts, events)
    }

    // MARK: - Contacts Seeding

    func seedContacts() async throws -> Int {
        let store = CNContactStore()
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .notDetermined {
            let granted = try await store.requestAccess(for: .contacts)
            guard granted else { return 0 }
        }

        let saveRequest = CNSaveRequest()
        var count = 0

        // 1. Regular Contacts
        let regularList: [(given: String, family: String, phone: String, email: String)] = [
            ("John", "Appleseed", "+1 (555) 010-1001", "john.appleseed@apple.com"),
            ("Alice", "Freeman", "+1 (555) 010-1002", "alice.freeman@example.com"),
            ("Bob", "Jenkins", "+1 (555) 010-1003", "bob.jenkins@work.com"),
            ("Clara", "Oswald", "+1 (555) 010-1004", "clara.oswald@tardis.org"),
            ("David", "Miller", "+1 (555) 010-1005", "david.m@company.com"),
            ("Emma", "Watson", "+1 (555) 010-1006", "emma.w@cinema.com"),
            ("Frank", "Wright", "+1 (555) 010-1007", "frank@design.com"),
            ("Grace", "Hopper", "+1 (555) 010-1008", "grace@navy.mil")
        ]

        for item in regularList {
            let contact = CNMutableContact()
            contact.givenName = item.given
            contact.familyName = item.family
            contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: item.phone))]
            contact.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: item.email as NSString)]
            saveRequest.add(contact, toContainerWithIdentifier: nil)
            count += 1
        }

        // 2. Duplicate Contacts (Same Phone Numbers to trigger duplicate detection)
        // Group 1: Michael Scott duplicates
        let scottGroup = [
            ("Michael", "Scott", "+1 (555) 019-9901", "Dunder Mifflin"),
            ("Mike", "Scott", "+1 (555) 019-9901", "Michael Scarn"),
            ("Michael G.", "Scott", "+1 (555) 019-9901", "Scranton Branch")
        ]
        for item in scottGroup {
            let contact = CNMutableContact()
            contact.givenName = item.0
            contact.familyName = item.1
            contact.organizationName = item.3
            contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: item.2))]
            saveRequest.add(contact, toContainerWithIdentifier: nil)
            count += 1
        }

        // Group 2: Sarah Connor duplicates
        let connorGroup = [
            ("Sarah", "Connor", "+1 (555) 019-8802", "Resistance HQ"),
            ("Sarah J.", "Connor", "+1 (555) 019-8802", "Cyberdyne Systems")
        ]
        for item in connorGroup {
            let contact = CNMutableContact()
            contact.givenName = item.0
            contact.familyName = item.1
            contact.organizationName = item.3
            contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: item.2))]
            saveRequest.add(contact, toContainerWithIdentifier: nil)
            count += 1
        }

        // 3. Incomplete Contacts (Missing phone OR missing name)
        // Missing phone:
        let noPhoneList = [
            ("Bruce", "Wayne", "bruce@wayne-enterprises.com"),
            ("Clark", "Kent", "clark@dailyplanet.com")
        ]
        for item in noPhoneList {
            let contact = CNMutableContact()
            contact.givenName = item.0
            contact.familyName = item.1
            contact.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: item.2 as NSString)]
            saveRequest.add(contact, toContainerWithIdentifier: nil)
            count += 1
        }

        // Missing name (only phone):
        let noNameList = [
            "+1 (555) 012-3456",
            "+1 (555) 098-7654"
        ]
        for phone in noNameList {
            let contact = CNMutableContact()
            contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: phone))]
            saveRequest.add(contact, toContainerWithIdentifier: nil)
            count += 1
        }

        try store.execute(saveRequest)
        return count
    }

    // MARK: - Calendar Seeding

    func seedCalendarEvents() async throws -> Int {
        let store = EKEventStore()
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .notDetermined {
            let granted = try await store.requestFullAccessToEvents()
            guard granted else { return 0 }
        } else if status != .fullAccess {
            return 0
        }

        guard let targetCalendar = store.defaultCalendarForNewEvents ?? store.calendars(for: .event).first(where: { $0.allowsContentModifications }) else {
            return 0
        }

        let now = Date()
        let calendar = Calendar.current
        var count = 0

        // Past events (from 2 years ago up to recent days)
        let pastEventsList: [(title: String, daysAgo: Int, durationHours: Double)] = [
            ("Dentist Appointment", 720, 1.0),
            ("Old Team Sync", 540, 1.5),
            ("Flight to New York", 360, 5.0),
            ("Hotel Booking NYC", 358, 24.0),
            ("Project Sprint Review", 180, 2.0),
            ("Car Service & Oil Change", 90, 1.5),
            ("Quarterly Planning", 60, 3.0),
            ("Lunch with Alex", 25, 1.0),
            ("Weekly Catchup", 14, 0.75),
            ("Conference Call with Client", 7, 1.0),
            ("Doctor Checkup", 3, 0.5)
        ]

        for item in pastEventsList {
            guard let eventDate = calendar.date(byAdding: .day, value: -item.daysAgo, to: now) else { continue }
            let event = EKEvent(eventStore: store)
            event.calendar = targetCalendar
            event.title = item.title
            event.startDate = eventDate
            event.endDate = eventDate.addingTimeInterval(item.durationHours * 3600)
            try store.save(event, span: .thisEvent, commit: false)
            count += 1
        }

        // Future events
        let futureEventsList: [(title: String, daysAhead: Int, durationHours: Double)] = [
            ("Team Standup Meeting", 2, 0.5),
            ("Product Demo & Walkthrough", 7, 1.0),
            ("Birthday Party", 18, 4.0),
            ("Tech Conference 2027", 45, 8.0),
            ("Summer Vacation Trip", 90, 72.0),
            ("Annual Medical Examination", 180, 1.5)
        ]

        for item in futureEventsList {
            guard let eventDate = calendar.date(byAdding: .day, value: item.daysAhead, to: now) else { continue }
            let event = EKEvent(eventStore: store)
            event.calendar = targetCalendar
            event.title = item.title
            event.startDate = eventDate
            event.endDate = eventDate.addingTimeInterval(item.durationHours * 3600)
            try store.save(event, span: .thisEvent, commit: false)
            count += 1
        }

        if count > 0 {
            try store.commit()
        }

        return count
    }
}
