import Foundation

/// Centralized version management
enum AppVersion {
    /// Current version - update this when releasing
    static let current = "2.0.0"

    /// App name
    static let name = "AppleRemindersMCP"

    /// Full display name
    static let displayName = "Apple Reminders MCP Server"

    /// Version string for display
    static var versionString: String {
        "\(name) \(current)"
    }

    /// Help message
    static var helpMessage: String {
        """
        \(displayName)

        Fork of che-ical-mcp by kiki830621 (MIT License)
        Enhanced with date-range filtering for list_reminders and search_reminders.

        Usage: \(name) [options]

        Options:
          --version, -v    Show version information
          --help, -h       Show this help message

        Version: \(current)
        Repository: https://github.com/patrickfreyer/apple-reminders-mcp
        """
    }
}
