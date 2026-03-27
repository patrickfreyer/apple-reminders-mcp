import XCTest
@testable import AppleRemindersMCP

/// Tests for tag extraction and building utilities
/// Tags are stored as #hashtags in reminder notes, compatible with Apple Reminders (macOS Ventura+)
final class TagUtilityTests: XCTestCase {

    // We test the tag logic through a helper that mirrors Server's implementation
    // Since Server's methods are private, we test the same regex logic directly

    // MARK: - Tag Extraction

    func testExtractTagsFromNotesWithTags() {
        let notes = "Buy milk and eggs\n#grocery #urgent"
        let (cleanNotes, tags) = extractTags(from: notes)
        XCTAssertEqual(cleanNotes, "Buy milk and eggs")
        XCTAssertEqual(tags, ["grocery", "urgent"])
    }

    func testExtractTagsFromNotesWithOnlyTags() {
        let notes = "#work #meeting"
        let (cleanNotes, tags) = extractTags(from: notes)
        XCTAssertNil(cleanNotes)
        XCTAssertEqual(tags, ["work", "meeting"])
    }

    func testExtractTagsFromNotesWithoutTags() {
        let notes = "Just a regular note"
        let (cleanNotes, tags) = extractTags(from: notes)
        XCTAssertEqual(cleanNotes, "Just a regular note")
        XCTAssertEqual(tags, [])
    }

    func testExtractTagsFromNilNotes() {
        let (cleanNotes, tags) = extractTags(from: nil)
        XCTAssertNil(cleanNotes)
        XCTAssertEqual(tags, [])
    }

    func testExtractTagsFromEmptyNotes() {
        let (cleanNotes, tags) = extractTags(from: "")
        XCTAssertNil(cleanNotes)
        XCTAssertEqual(tags, [])
    }

    func testExtractTagsWithMultilineNotes() {
        let notes = "First line\nSecond line\n#tag1 #tag2"
        let (cleanNotes, tags) = extractTags(from: notes)
        XCTAssertEqual(cleanNotes, "First line\nSecond line")
        XCTAssertEqual(tags, ["tag1", "tag2"])
    }

    func testExtractTagsWithTrailingEmptyLines() {
        let notes = "Note content\n#tag1\n"
        let (cleanNotes, tags) = extractTags(from: notes)
        XCTAssertEqual(cleanNotes, "Note content")
        XCTAssertEqual(tags, ["tag1"])
    }

    func testExtractTagsIgnoresHashInMiddleOfText() {
        // Tags are only on the last non-empty line that is ENTIRELY #tags
        let notes = "Issue #123 is important"
        let (cleanNotes, tags) = extractTags(from: notes)
        XCTAssertEqual(cleanNotes, "Issue #123 is important")
        XCTAssertEqual(tags, [])
    }

    func testExtractTagsWithCJKCharacters() {
        let notes = "買牛奶\n#買菜 #緊急"
        let (cleanNotes, tags) = extractTags(from: notes)
        XCTAssertEqual(cleanNotes, "買牛奶")
        XCTAssertEqual(tags, ["買菜", "緊急"])
    }

    // MARK: - Building Notes with Tags

    func testBuildNotesWithTagsAndNotes() {
        let result = buildNotesWithTags(notes: "Buy groceries", tags: ["grocery", "urgent"])
        XCTAssertEqual(result, "Buy groceries\n#grocery #urgent")
    }

    func testBuildNotesWithTagsOnly() {
        let result = buildNotesWithTags(notes: nil, tags: ["work"])
        XCTAssertEqual(result, "#work")
    }

    func testBuildNotesWithEmptyTags() {
        let result = buildNotesWithTags(notes: "Some notes", tags: [])
        XCTAssertEqual(result, "Some notes")
    }

    func testBuildNotesStripsHashPrefix() {
        let result = buildNotesWithTags(notes: nil, tags: ["#already_prefixed", "normal"])
        XCTAssertEqual(result, "#already_prefixed #normal")
    }

    func testBuildNotesWithNilNotesAndEmptyTags() {
        let result = buildNotesWithTags(notes: nil, tags: [])
        XCTAssertNil(result)
    }

    // MARK: - Round-trip (build then extract)

    func testRoundTripWithNotesAndTags() {
        let originalNotes = "Remember to call dentist"
        let originalTags = ["health", "phone"]

        let combined = buildNotesWithTags(notes: originalNotes, tags: originalTags)!
        let (extractedNotes, extractedTags) = extractTags(from: combined)

        XCTAssertEqual(extractedNotes, originalNotes)
        XCTAssertEqual(extractedTags, originalTags)
    }

    func testRoundTripWithTagsOnly() {
        let originalTags = ["work", "urgent"]

        let combined = buildNotesWithTags(notes: nil, tags: originalTags)!
        let (extractedNotes, extractedTags) = extractTags(from: combined)

        XCTAssertNil(extractedNotes)
        XCTAssertEqual(extractedTags, originalTags)
    }

    // MARK: - Helper functions (mirror Server's private implementation)

    private func extractTags(from notes: String?) -> (cleanNotes: String?, tags: [String]) {
        guard let notes = notes, !notes.isEmpty else {
            return (nil, [])
        }

        let tagPattern = #"#(\S+)"#
        let regex = try! NSRegularExpression(pattern: tagPattern)

        let lines = notes.components(separatedBy: "\n")
        var tagLine: String?
        var tagLineIndex: Int?

        let tagLinePattern = #"^\s*(#\S+\s*)+$"#
        let tagLineRegex = try! NSRegularExpression(pattern: tagLinePattern)

        for i in stride(from: lines.count - 1, through: 0, by: -1) {
            let line = lines[i]
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let range = NSRange(line.startIndex..., in: line)
            if tagLineRegex.firstMatch(in: line, range: range) != nil {
                tagLine = line
                tagLineIndex = i
            }
            break
        }

        guard let foundTagLine = tagLine, let foundIndex = tagLineIndex else {
            return (notes, [])
        }

        let range = NSRange(foundTagLine.startIndex..., in: foundTagLine)
        let matches = regex.matches(in: foundTagLine, range: range)
        let tags = matches.compactMap { match -> String? in
            guard let tagRange = Range(match.range(at: 1), in: foundTagLine) else { return nil }
            return String(foundTagLine[tagRange])
        }

        if tags.isEmpty {
            return (notes, [])
        }

        var cleanLines = lines
        cleanLines.remove(at: foundIndex)
        while let last = cleanLines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            cleanLines.removeLast()
        }
        let cleanNotes = cleanLines.isEmpty ? nil : cleanLines.joined(separator: "\n")

        return (cleanNotes, tags)
    }

    private func buildNotesWithTags(notes: String?, tags: [String]) -> String? {
        let cleanTags = tags.map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }
            .filter { !$0.isEmpty }

        if cleanTags.isEmpty {
            return notes
        }

        let tagLine = cleanTags.map { "#\($0)" }.joined(separator: " ")

        if let notes = notes, !notes.isEmpty {
            return "\(notes)\n\(tagLine)"
        } else {
            return tagLine
        }
    }
}
