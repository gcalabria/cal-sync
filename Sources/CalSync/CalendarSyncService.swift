import EventKit
import Foundation

struct SyncStats {
    var created = 0
    var updated = 0
    var deleted = 0
    var errors = 0
    var errorMessages: [String] = []

    mutating func addError(_ message: String) {
        errors += 1
        errorMessages.append(message)
        Logger.shared.error(message)
    }
}

class CalendarSyncService {
    static let shared = CalendarSyncService()
    let eventStore = EKEventStore()
    private let syncState = SyncState.shared
    private let syncQueue = DispatchQueue(label: "com.calsync.sync", qos: .userInitiated)

    // MARK: - Permissions

    func requestAccess(completion: @escaping (Bool) -> Void) {
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToEvents { granted, error in
                if let error = error {
                    Logger.shared.error("Calendar access error: \(error)")
                }
                completion(granted)
            }
        } else {
            eventStore.requestAccess(to: .event) { granted, error in
                if let error = error {
                    Logger.shared.error("Calendar access error: \(error)")
                }
                completion(granted)
            }
        }
    }

    // MARK: - Calendar Discovery

    func availableCalendars() -> [EKCalendar] {
        return eventStore.calendars(for: .event)
    }

    func writableCalendars() -> [EKCalendar] {
        return eventStore.calendars(for: .event).filter { $0.allowsContentModifications }
    }

    func calendar(withIdentifier id: String) -> EKCalendar? {
        return eventStore.calendar(withIdentifier: id)
    }

    // MARK: - Sync

    func sync(completion: @escaping (Result<SyncStats, Error>) -> Void) {
        syncQueue.async { [weak self] in
            guard let self = self else { return }

            let settings = Settings.shared
            guard let sourceId = settings.sourceCalendarId,
                  let destId = settings.destinationCalendarId,
                  let sourceCal = self.calendar(withIdentifier: sourceId),
                  let destCal = self.calendar(withIdentifier: destId) else {
                completion(.failure(SyncError.calendarsNotConfigured))
                return
            }

            var stats = SyncStats()
            Logger.shared.info("Starting sync: \(sourceCal.title) → \(destCal.title)")

            // Forward sync: source → destination
            self.syncEvents(from: sourceCal, to: destCal, stats: &stats)

            // Reverse sync if two-way
            if settings.syncDirection == .twoWay {
                self.syncEvents(from: destCal, to: sourceCal, stats: &stats)
            }

            Logger.shared.info("Sync complete — Created: \(stats.created), Updated: \(stats.updated), Deleted: \(stats.deleted), Errors: \(stats.errors)")
            completion(.success(stats))
        }
    }

    private func syncEvents(from source: EKCalendar, to destination: EKCalendar, stats: inout SyncStats) {
        let now = Date()
        // EventKit limits predicates to ~4 years
        let fourYears: TimeInterval = 4 * 365.25 * 24 * 3600
        let endDate = now.addingTimeInterval(fourYears)

        let predicate = eventStore.predicateForEvents(withStart: now, end: endDate, calendars: [source])
        let sourceEvents = eventStore.events(matching: predicate)

        var processedSourceIds = Set<String>()

        for sourceEvent in sourceEvents {
            let sourceId = sourceEvent.calendarItemExternalIdentifier ?? ""
            guard !sourceId.isEmpty else { continue }

            // Skip events that were themselves created by sync (prevents loops in two-way mode)
            if syncState.destinationExternalIds().contains(sourceId) {
                continue
            }

            processedSourceIds.insert(sourceId)

            if let existing = syncState.record(forSourceId: sourceId) {
                // Event was previously synced — check if source was modified
                if let sourceModified = sourceEvent.lastModifiedDate,
                   sourceModified > existing.sourceLastModified {
                    // Source changed — update destination
                    if updateDestinationEvent(
                        destinationExternalId: existing.destinationExternalId,
                        from: sourceEvent,
                        destinationCalendar: destination
                    ) {
                        syncState.upsert(
                            sourceExternalId: sourceId,
                            destinationExternalId: existing.destinationExternalId,
                            destinationCalendarId: destination.calendarIdentifier,
                            sourceLastModified: sourceModified
                        )
                        stats.updated += 1
                    } else {
                        stats.addError("Failed to update event '\(sourceEvent.title ?? "untitled")' (sourceId: \(sourceId))")
                    }
                }
                // Else: source unchanged, skip
            } else {
                // New event — check for duplicates first
                if isDuplicate(of: sourceEvent, in: destination) {
                    continue
                }

                // Create in destination
                if let destExternalId = createEvent(from: sourceEvent, in: destination) {
                    syncState.upsert(
                        sourceExternalId: sourceId,
                        destinationExternalId: destExternalId,
                        destinationCalendarId: destination.calendarIdentifier,
                        sourceLastModified: sourceEvent.lastModifiedDate ?? now
                    )
                    stats.created += 1
                } else {
                    stats.addError("Failed to create event '\(sourceEvent.title ?? "untitled")' in destination")
                }
            }
        }

        // Orphan cleanup: remove destination events whose source no longer exists
        let allTracked = syncState.allRecords().filter { $0.destinationCalendarId == destination.calendarIdentifier }
        for record in allTracked {
            if !processedSourceIds.contains(record.sourceExternalId) {
                if deleteDestinationEvent(externalId: record.destinationExternalId) {
                    syncState.remove(forSourceId: record.sourceExternalId)
                    stats.deleted += 1
                } else {
                    stats.addError("Failed to delete orphaned event (externalId: \(record.destinationExternalId))")
                }
            }
        }
    }

    // MARK: - Event Operations

    private func createEvent(from source: EKEvent, in calendar: EKCalendar) -> String? {
        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        copyEventFields(from: source, to: event)

        do {
            try eventStore.save(event, span: .futureEvents, commit: true)
            return event.calendarItemExternalIdentifier
        } catch {
            Logger.shared.error("Failed to create event '\(source.title ?? "")': \(error)")
            return nil
        }
    }

    private func updateDestinationEvent(destinationExternalId: String, from source: EKEvent, destinationCalendar: EKCalendar) -> Bool {
        // Find the destination event by external identifier
        guard let destEvent = findEvent(byExternalId: destinationExternalId, in: destinationCalendar) else {
            Logger.shared.error("Destination event not found for update: \(destinationExternalId)")
            return false
        }

        copyEventFields(from: source, to: destEvent)

        do {
            try eventStore.save(destEvent, span: .futureEvents, commit: true)
            return true
        } catch {
            Logger.shared.error("Failed to update event '\(source.title ?? "")': \(error)")
            return false
        }
    }

    private func deleteDestinationEvent(externalId: String) -> Bool {
        // Search in all calendars for the event
        let calendars = eventStore.calendars(for: .event)
        for cal in calendars {
            if let event = findEvent(byExternalId: externalId, in: cal) {
                do {
                    try eventStore.remove(event, span: .futureEvents, commit: true)
                    return true
                } catch {
                    Logger.shared.error("Failed to delete event: \(error)")
                    return false
                }
            }
        }
        // Event already gone — consider it a success
        return true
    }

    private func findEvent(byExternalId externalId: String, in calendar: EKCalendar) -> EKEvent? {
        let now = Date()
        let fourYears: TimeInterval = 4 * 365.25 * 24 * 3600
        let predicate = eventStore.predicateForEvents(withStart: now, end: now.addingTimeInterval(fourYears), calendars: [calendar])
        let events = eventStore.events(matching: predicate)
        return events.first { $0.calendarItemExternalIdentifier == externalId }
    }

    private func copyEventFields(from source: EKEvent, to dest: EKEvent) {
        dest.title = source.title
        dest.startDate = source.startDate
        dest.endDate = source.endDate
        dest.isAllDay = source.isAllDay
        dest.location = source.location
        dest.structuredLocation = source.structuredLocation?.copy() as? EKStructuredLocation
        dest.url = source.url
        dest.availability = source.availability

        // Notes: copy original + append attendee info
        var notes = source.notes ?? ""
        if let attendees = source.attendees, !attendees.isEmpty {
            let names = attendees.compactMap { $0.name ?? $0.url.absoluteString }.joined(separator: ", ")
            let attendeeBlock = "\n\n[Attendees: \(names)]"
            // Only append if not already present
            if !notes.contains("[Attendees:") {
                notes += attendeeBlock
            }
        }
        dest.notes = notes

        // Alarms
        if let existingAlarms = dest.alarms {
            for alarm in existingAlarms {
                dest.removeAlarm(alarm)
            }
        }
        if let sourceAlarms = source.alarms {
            for alarm in sourceAlarms {
                let newAlarm = EKAlarm(relativeOffset: alarm.relativeOffset)
                dest.addAlarm(newAlarm)
            }
        }

        // Recurrence rules
        if let existingRules = dest.recurrenceRules {
            for rule in existingRules {
                dest.removeRecurrenceRule(rule)
            }
        }
        if let sourceRules = source.recurrenceRules {
            for rule in sourceRules {
                dest.addRecurrenceRule(rule)
            }
        }
    }

    // MARK: - Deduplication

    private func isDuplicate(of event: EKEvent, in calendar: EKCalendar) -> Bool {
        guard let start = event.startDate else { return false }
        let window: TimeInterval = 60 // ±1 minute
        let predicate = eventStore.predicateForEvents(
            withStart: start.addingTimeInterval(-window),
            end: start.addingTimeInterval(window),
            calendars: [calendar]
        )
        let existing = eventStore.events(matching: predicate)
        return existing.contains { $0.title == event.title }
    }
}

// MARK: - Errors

enum SyncError: LocalizedError {
    case calendarsNotConfigured
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .calendarsNotConfigured:
            return "Source and destination calendars are not configured. Please open Settings."
        case .permissionDenied:
            return "Calendar access was denied. Please grant access in System Settings > Privacy & Security > Calendars."
        }
    }
}
