// WorkspaceScanner — file discovery, frontmatter parsing, and filesystem watching.

import Foundation
import Yams

/// The result of parsing a Markdown file's YAML frontmatter.
public struct ParsedFrontmatter: Sendable, Equatable {
  /// All top-level string key-value pairs from the frontmatter.
  public var fields: [String: String]

  /// The body content after the frontmatter (everything after the closing `---`).
  public var body: String

  public init(fields: [String: String] = [:], body: String = "") {
    self.fields = fields
    self.body = body
  }
}

/// Parses YAML frontmatter from Markdown content.
public enum FrontmatterParser {
  /// Parses the YAML frontmatter block from Markdown content.
  ///
  /// Frontmatter must start at the very beginning of the file with a `---` line
  /// and end with another `---` line. If no valid frontmatter is found, returns
  /// empty fields and the full content as the body.
  ///
  /// Only top-level string key-value pairs are extracted. Nested structures are
  /// skipped.
  public static func parse(_ content: String) -> ParsedFrontmatter {
    let lines = content.components(separatedBy: "\n")

    // Frontmatter must start at line 0 with exactly "---".
    guard !lines.isEmpty, lines[0].trimmingCharacters(in: .whitespaces) == "---" else {
      return ParsedFrontmatter(fields: [:], body: content)
    }

    // Find the closing "---".
    var closingIndex: Int?
    for i in 1 ..< lines.count {
      if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
        closingIndex = i
        break
      }
    }

    guard let endIndex = closingIndex else {
      // No closing delimiter — treat the whole file as body with no frontmatter.
      return ParsedFrontmatter(fields: [:], body: content)
    }

    let yamlLines = lines[1 ..< endIndex]
    let yamlString = yamlLines.joined(separator: "\n")

    // Body is everything after the closing "---" line.
    let bodyLines = lines[(endIndex + 1)...]
    let body = bodyLines.joined(separator: "\n")

    // Parse the YAML.
    let fields = parseYAMLFields(yamlString)

    return ParsedFrontmatter(fields: fields, body: body)
  }

  /// Extracts the title from the first `# Heading` line in the body.
  ///
  /// Looks for a line starting with `# ` (H1 in Markdown). Returns `nil` if
  /// no heading is found.
  public static func extractHeadingTitle(from body: String) -> String? {
    let lines = body.components(separatedBy: "\n")
    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("# ") {
        let title = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : title
      }
    }
    return nil
  }

  /// Parses a YAML string and extracts only top-level string key-value pairs.
  private static func parseYAMLFields(_ yaml: String) -> [String: String] {
    guard !yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return [:]
    }

    guard let parsed = try? Yams.load(yaml: yaml) else {
      return [:]
    }

    guard let dict = parsed as? [String: Any] else {
      return [:]
    }

    var fields: [String: String] = [:]
    for (key, value) in dict {
      if let stringValue = value as? String {
        fields[key] = stringValue
      } else if let intValue = value as? Int {
        fields[key] = String(intValue)
      } else if let doubleValue = value as? Double {
        fields[key] = String(doubleValue)
      } else if let boolValue = value as? Bool {
        fields[key] = String(boolValue)
      }
      // Skip nested structures (arrays, dicts, etc.)
    }

    return fields
  }
}
