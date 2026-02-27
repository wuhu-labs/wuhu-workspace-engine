/// A path-based rule that assigns a kind to documents matching a glob pattern.
///
/// Rules are checked in order when a document has no `kind` in its frontmatter.
/// The first rule whose glob pattern matches the document's workspace-relative
/// path determines the document's kind.
///
/// Glob patterns support:
/// - `*` — matches any characters within a single path segment (no `/`)
/// - `**` — matches zero or more path segments (including nested directories)
///
/// Example:
/// ```yaml
/// rules:
///   - path: "issues/**"
///     kind: issue
///   - path: "docs/architecture/**"
///     kind: architecture
/// ```
public struct Rule: Sendable, Hashable, Codable {
  /// The glob pattern to match against document paths.
  public var path: String

  /// The kind to assign to matching documents.
  public var kind: Kind

  public init(path: String, kind: Kind) {
    self.path = path
    self.kind = kind
  }
}
