import Foundation

/// Attendee input passed in from the tool layer.
public struct AttendeeInput {
    public let email: String
    public let name: String?

    public init(email: String, name: String?) {
        self.email = email
        self.name = name
    }
}

/// Errors specific to attendee invitation flow.
enum AttendeeError: LocalizedError {
    case missingCalendarName
    case missingEventUID
    case noValidAttendees
    case calendarAppFailed(stderr: String, status: Int32)
    case eventNotFoundInCalendarApp(uid: String, calendar: String)
    case appleScriptTimeout(stderr: String)

    var errorDescription: String? {
        switch self {
        case .missingCalendarName:
            return "Attendees require a calendar_name (so we can target the right Calendar.app calendar)."
        case .missingEventUID:
            return "Could not derive the event UID needed for AppleScript attendee invitation."
        case .noValidAttendees:
            return "Attendees array contained no entries with a non-empty email."
        case .calendarAppFailed(let stderr, let status):
            return "Calendar.app AppleScript failed (exit \(status)): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .eventNotFoundInCalendarApp(let uid, let calendar):
            return """
            Calendar.app could not find an event with UID '\(uid)' in calendar '\(calendar)'. \
            The event was created/updated in EventKit but invites were NOT sent. \
            This can happen if Calendar.app has not yet synced the new event, the calendar name \
            does not match exactly, or the event lives on a calendar that does not support invites \
            (e.g. local-only calendars).
            """
        case .appleScriptTimeout(let stderr):
            return """
            Calendar.app's AppleScript bridge timed out (-1712). This commonly happens when \
            Calendar.app is mid-sync after a prior invite send (Exchange-backed calendars). \
            Auto-recovery (restart Calendar.app + retry) was attempted and also failed. \
            Raw stderr: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            """
        }
    }
}

/// Bridges EventKit (which exposes attendees as read-only) to Calendar.app via AppleScript
/// so we can actually add invitees to a created/updated event.
///
/// Known limitations:
///   - Only works for calendars that support invites (iCloud, Exchange/CalDAV). Local-only
///     calendars will silently accept the attendee but no invitation email is sent.
///   - Requires Calendar.app to be running (we auto-launch it if needed).
///   - Calendar.app must already have synced the EventKit write before we look it up by UID.
struct AttendeeManager {

    /// Add attendees to an event in the named Calendar.app calendar.
    /// Identifies the event by UID (primary) with an optional title+start fallback for the
    /// case where Calendar.app's local cache hasn't picked up the EventKit write yet.
    /// Throws `AttendeeError` on failure.
    static func addAttendees(
        eventUID: String,
        calendarName: String,
        attendees: [AttendeeInput],
        fallbackTitle: String? = nil,
        fallbackStartDate: Date? = nil
    ) throws {
        let validAttendees = attendees.filter { !$0.email.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !validAttendees.isEmpty else {
            throw AttendeeError.noValidAttendees
        }
        guard !eventUID.isEmpty else { throw AttendeeError.missingEventUID }
        guard !calendarName.isEmpty else { throw AttendeeError.missingCalendarName }

        // Make sure Calendar.app is running so it can resolve the UID.
        ensureCalendarAppLaunched()

        let script = buildAppleScript(
            eventUID: eventUID,
            calendarName: calendarName,
            attendees: validAttendees,
            fallbackTitle: fallbackTitle,
            fallbackStartDate: fallbackStartDate
        )

        // First attempt — runs the full cache-lag retry loop. If the AppleScript bridge
        // is locked (Calendar.app mid-sync after a previous invite send), this raises
        // `appleScriptTimeout`; we restart Calendar.app once and retry the whole loop.
        do {
            try runWithCacheLagRetry(script: script, eventUID: eventUID, calendarName: calendarName)
            return
        } catch AttendeeError.appleScriptTimeout {
            restartCalendarApp()
            // Single retry after restart — if this also fails, propagate.
            try runWithCacheLagRetry(script: script, eventUID: eventUID, calendarName: calendarName)
        }
    }

    /// Inner retry loop that handles the "Calendar.app hasn't synced the new event yet" race
    /// by backing off and re-asking up to 6 times. Caller is responsible for handling
    /// `appleScriptTimeout`, which signals a bridge lock that needs a Calendar.app restart.
    private static func runWithCacheLagRetry(
        script: String,
        eventUID: String,
        calendarName: String
    ) throws {
        let maxAttempts = 6
        var lastError: Error?
        for attempt in 0..<maxAttempts {
            do {
                try runOsascript(script, eventUID: eventUID, calendarName: calendarName)
                return
            } catch AttendeeError.eventNotFoundInCalendarApp {
                lastError = AttendeeError.eventNotFoundInCalendarApp(uid: eventUID, calendar: calendarName)
                // Back off: 0.5s, 1.0s, 1.5s, 2.0s, 2.5s (cumulative ~7.5s worst case)
                Thread.sleep(forTimeInterval: 0.5 * Double(attempt + 1))
                continue
            } catch {
                throw error
            }
        }
        if let lastError = lastError { throw lastError }
    }

    // MARK: - AppleScript

    /// Build the AppleScript that finds the event (by UID, with optional title+start fallback)
    /// inside the named calendar and appends new attendees to it.
    static func buildAppleScript(
        eventUID: String,
        calendarName: String,
        attendees: [AttendeeInput],
        fallbackTitle: String? = nil,
        fallbackStartDate: Date? = nil
    ) -> String {
        let escapedUID = escapeForAppleScript(eventUID)
        let escapedCalendar = escapeForAppleScript(calendarName)

        var attendeeLines: [String] = []
        for attendee in attendees {
            let escapedEmail = escapeForAppleScript(attendee.email)
            let displayName = attendee.name?.isEmpty == false ? attendee.name! : attendee.email
            let escapedName = escapeForAppleScript(displayName)
            attendeeLines.append(
                #"            make new attendee at end of attendees with properties {email:"\#(escapedEmail)", display name:"\#(escapedName)"}"#
            )
        }
        let attendeeBlock = attendeeLines.joined(separator: "\n")

        // Build the fallback lookup branch if we have a title + start date.
        // We match by exact title + start time within a 1-minute window.
        var fallbackBlock = ""
        if let title = fallbackTitle, let start = fallbackStartDate {
            let escapedTitle = escapeForAppleScript(title)
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            f.timeZone = TimeZone.current
            let startStr = f.string(from: start)
            // Build a string like "yyyy-MM-dd HH:mm:ss" for AppleScript date construction below
            let asDate = startStr.replacingOccurrences(of: "T", with: " ")
            fallbackBlock = """

                if (count of matchedEvents) is 0 then
                    -- Fallback: match by title + start time (±60s) in case the just-created
                    -- event's UID is not yet visible to Calendar.app's local cache.
                    set targetStart to (current date)
                    set year of targetStart to (text 1 thru 4 of "\(asDate)") as integer
                    set month of targetStart to (text 6 thru 7 of "\(asDate)") as integer
                    set day of targetStart to (text 9 thru 10 of "\(asDate)") as integer
                    set hours of targetStart to (text 12 thru 13 of "\(asDate)") as integer
                    set minutes of targetStart to (text 15 thru 16 of "\(asDate)") as integer
                    set seconds of targetStart to (text 18 thru 19 of "\(asDate)") as integer
                    set winLow to targetStart - 60
                    set winHigh to targetStart + 60
                    set matchedEvents to (every event whose summary is "\(escapedTitle)" and start date ≥ winLow and start date ≤ winHigh)
                end if
        """
        }

        // Note: `whose uid is "..."` is fast and avoids walking every event.
        // We wrap in a try so we can return a structured error if the UID is not found.
        return """
        tell application "Calendar"
            try
                tell calendar "\(escapedCalendar)"
                    set matchedEvents to (every event whose uid is "\(escapedUID)")\(fallbackBlock)
                    if (count of matchedEvents) is 0 then
                        error "EVENT_NOT_FOUND"
                    end if
                    set targetEvent to item 1 of matchedEvents
                    tell targetEvent
        \(attendeeBlock)
                    end tell
                end tell
                return "OK"
            on error errMsg number errNum
                if errMsg is "EVENT_NOT_FOUND" then
                    error "EVENT_NOT_FOUND_BY_UID"
                else
                    error errMsg number errNum
                end if
            end try
        end tell
        """
    }

    /// Escape a string for safe use inside an AppleScript double-quoted literal.
    static func escapeForAppleScript(_ s: String) -> String {
        // AppleScript uses backslash escapes inside double-quoted strings.
        var out = s
        out = out.replacingOccurrences(of: "\\", with: "\\\\")
        out = out.replacingOccurrences(of: "\"", with: "\\\"")
        return out
    }

    // MARK: - Process execution

    private static func runOsascript(_ script: String, eventUID: String, calendarName: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            if stderr.contains("EVENT_NOT_FOUND_BY_UID") {
                throw AttendeeError.eventNotFoundInCalendarApp(uid: eventUID, calendar: calendarName)
            }
            // Detect AppleEvent timeout (-1712): Calendar.app's AppleScript bridge is locked,
            // typically because it's mid-sync after a prior invite send. The caller can recover
            // by restarting Calendar.app and retrying.
            if stderr.contains("-1712") || stderr.contains("AppleEvent timed out") {
                throw AttendeeError.appleScriptTimeout(stderr: stderr)
            }
            throw AttendeeError.calendarAppFailed(stderr: stderr, status: process.terminationStatus)
        }
    }

    /// Launch Calendar.app if it is not already running. We don't bring it to the foreground.
    private static func ensureCalendarAppLaunched() {
        let launchScript = """
        tell application "System Events"
            if not (exists process "Calendar") then
                tell application "Calendar" to launch
            end if
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", launchScript]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // Best-effort; if this fails the main AppleScript will surface a clearer error.
        }
    }

    /// Quit and relaunch Calendar.app. Used when the AppleScript bridge is locked
    /// (typically because Calendar.app is mid-sync after a previous invite send to an
    /// Exchange-backed calendar). After a fresh launch the bridge accepts attendee writes again.
    /// Total cost: ~10s of sleep — only invoked after a -1712 timeout, so it's not on the hot path.
    private static func restartCalendarApp() {
        // Quit
        let quitProcess = Process()
        quitProcess.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        quitProcess.arguments = ["-e", "tell application \"Calendar\" to quit"]
        quitProcess.standardOutput = Pipe()
        quitProcess.standardError = Pipe()
        try? quitProcess.run()
        quitProcess.waitUntilExit()

        // Wait for Calendar.app to fully exit before relaunching.
        Thread.sleep(forTimeInterval: 4.0)

        // Relaunch via `open -a` (doesn't require it to be in the foreground).
        let openProcess = Process()
        openProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        openProcess.arguments = ["-a", "Calendar"]
        openProcess.standardOutput = Pipe()
        openProcess.standardError = Pipe()
        try? openProcess.run()
        openProcess.waitUntilExit()

        // Wait for Calendar.app to be ready to accept AppleScript again.
        Thread.sleep(forTimeInterval: 6.0)
    }
}
