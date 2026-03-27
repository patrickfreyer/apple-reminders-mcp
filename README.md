# AppleRemindersMCP

Native Swift/EventKit MCP server for macOS Calendar and Reminders. 25 tools for full calendar event and reminder management via the Model Context Protocol.

**v2.0.0** -- Fork of [che-ical-mcp](https://github.com/kiki830621/che-ical-mcp) by Che Cheng (kiki830621).

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue)](https://www.apple.com/macos/)
[![MCP Swift SDK](https://img.shields.io/badge/MCP_Swift_SDK-0.11.0-green)](https://github.com/modelcontextprotocol/swift-sdk)

---

## Fork enhancements

This fork adds `due_before` and `due_after` date-range filtering parameters to `list_reminders` and `search_reminders`. These filters operate at the EventKit query level, making reminder queries significantly more efficient when you only need reminders within a specific date window (e.g., "reminders due this week") instead of fetching all reminders and filtering client-side.

Both parameters accept ISO8601 (`2026-03-27T09:00:00`) or date-only (`2026-03-27`) format.

---

## Installation

### Binary install (recommended)

```bash
mkdir -p ~/bin

curl -L https://github.com/patrickfreyer/apple-reminders-mcp/releases/latest/download/AppleRemindersMCP \
  -o ~/bin/AppleRemindersMCP
chmod +x ~/bin/AppleRemindersMCP

claude mcp add --scope user --transport stdio apple-reminders-mcp -- ~/bin/AppleRemindersMCP
```

On first use, macOS will prompt for **Calendar** and **Reminders** access. Click Allow for both.

### Claude Desktop

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "apple-reminders-mcp": {
      "command": "/Users/YOU/bin/AppleRemindersMCP"
    }
  }
}
```

---

## Tools (25)

### Calendars (4)

| Tool | Description |
|------|-------------|
| `list_calendars` | List all calendars and reminder lists with source type |
| `create_calendar` | Create a new calendar |
| `update_calendar` | Rename a calendar or change its color |
| `delete_calendar` | Delete a calendar |

### Events (4)

| Tool | Description |
|------|-------------|
| `list_events` | List events with filter (all/past/future/all_day), sort, and limit |
| `create_event` | Create an event with reminders, location, URL, and recurrence |
| `update_event` | Update an event |
| `delete_event` | Delete an event |

### Reminders (7)

| Tool | Description |
|------|-------------|
| `list_reminders` | List reminders with filter/sort/limit, tag extraction, `due_before`/`due_after` |
| `create_reminder` | Create a reminder with due date, priority, tags, location trigger, recurrence |
| `update_reminder` | Update a reminder including tags |
| `complete_reminder` | Mark a reminder as completed or incomplete |
| `delete_reminder` | Delete a reminder |
| `search_reminders` | Search reminders by keyword(s) or tag with `due_before`/`due_after` |
| `list_reminder_tags` | List all unique tags with usage counts |

### Advanced (10)

| Tool | Description |
|------|-------------|
| `search_events` | Search events by keyword(s) with AND/OR matching |
| `list_events_quick` | Quick shortcuts: `today`, `tomorrow`, `this_week`, `next_7_days`, etc. |
| `create_events_batch` | Create multiple events at once with duplicate detection |
| `check_conflicts` | Check for overlapping events in a time range |
| `copy_event` | Copy an event to another calendar (with optional move) |
| `move_events_batch` | Move multiple events to another calendar |
| `delete_events_batch` | Delete events by IDs or date range with dry-run preview |
| `find_duplicate_events` | Find duplicate events across calendars |
| `create_reminders_batch` | Create multiple reminders at once |
| `delete_reminders_batch` | Delete multiple reminders at once |

---

## Key features

- **Date filtering** -- `due_before`/`due_after` on reminder queries for efficient date-scoped lookups
- **Tags** -- `#hashtag` support in reminder notes with `list_reminder_tags` aggregation
- **Batch operations** -- Batch create, move, and delete for both events and reminders
- **Location triggers** -- Geofence-based reminder triggers (enter/leave) with structured coordinates
- **Recurrence** -- Daily, weekly, monthly, yearly recurrence for events and reminders
- **Flexible date parsing** -- ISO8601, date-only, time-only, and timezone-aware formats
- **Duplicate detection** -- Idempotent create operations that check-before-write on retry
- **Conflict detection** -- Check for overlapping events before scheduling
- **Source disambiguation** -- `calendar_source` parameter for same-name calendars across iCloud, Google, Exchange, etc.
- **Fuzzy calendar matching** -- Case-insensitive calendar name resolution

---

## Building from source

```bash
git clone https://github.com/patrickfreyer/apple-reminders-mcp.git
cd apple-reminders-mcp
swift build -c release
cp .build/release/AppleRemindersMCP ~/bin/
```

Requires Xcode Command Line Tools. On macOS 26 (Tahoe), you may need Homebrew Swift (`brew install swift`) if the system toolchain is not yet available.

---

## License

MIT License. See [LICENSE](LICENSE) for details.

Originally created by [Che Cheng](https://github.com/kiki830621) (che-ical-mcp). This fork is maintained by [Patrick Freyer](https://github.com/patrickfreyer).
