// WorkspaceContracts — types and protocols for the workspace engine.
// This target has no external dependencies and is safe to import from iOS apps.

/// Identifies a document kind (e.g., "document", "issue").
public struct Kind: Sendable, Hashable, Codable, RawRepresentable {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let document = Kind(rawValue: "document")
  public static let issue = Kind(rawValue: "issue")
}
