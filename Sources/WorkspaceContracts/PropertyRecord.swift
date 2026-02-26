/// A row in the `properties` table — a single key-value pair for a document.
///
/// All frontmatter key-values are stored here, even if they also appear in a
/// kind-specific extension table. This enables uniform ad-hoc queries.
public struct PropertyRecord: Sendable, Hashable, Codable {
  /// Workspace-relative path to the document (FK to `docs`).
  public var path: String

  /// The property key (e.g., "status", "priority").
  public var key: String

  /// The property value, stored as a string.
  public var value: String

  public init(path: String, key: String, value: String) {
    self.path = path
    self.key = key
    self.value = value
  }
}
