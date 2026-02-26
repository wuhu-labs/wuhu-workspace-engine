/// A fully-loaded document: its base record plus all its properties.
///
/// This is the primary type returned by query results.
public struct WorkspaceDocument: Sendable, Hashable, Codable {
  /// The base document record (path, kind, title).
  public var record: DocumentRecord

  /// All frontmatter properties as a flat dictionary.
  public var properties: [String: String]

  public init(record: DocumentRecord, properties: [String: String] = [:]) {
    self.record = record
    self.properties = properties
  }
}

public extension WorkspaceDocument {
  /// Convenience accessor for the document path.
  var path: String {
    record.path
  }

  /// Convenience accessor for the document kind.
  var kind: Kind {
    record.kind
  }

  /// Convenience accessor for the document title.
  var title: String? {
    record.title
  }
}
