/// A row in the `docs` table — the universal metadata every document has.
public struct DocumentRecord: Sendable, Hashable, Codable {
  /// Workspace-relative path to the Markdown file (primary key).
  public var path: String

  /// The kind of this document (e.g., "document", "issue").
  public var kind: Kind

  /// The document title, typically from frontmatter or the first heading.
  public var title: String?

  public init(path: String, kind: Kind, title: String? = nil) {
    self.path = path
    self.kind = kind
    self.title = title
  }
}
