/// Describes a kind and its known property keys.
///
/// Built-in kinds have hardcoded definitions; custom kinds are parsed from `wuhu.yml`.
/// The engine uses `properties` to determine which columns to create in the kind's
/// extension table.
public struct KindDefinition: Sendable, Hashable, Codable {
  /// The kind this definition describes.
  public var kind: Kind

  /// Known property keys for this kind (column names in its extension table).
  /// Order is preserved for deterministic schema creation.
  public var properties: [String]

  public init(kind: Kind, properties: [String]) {
    self.kind = kind
    self.properties = properties
  }
}

public extension KindDefinition {
  /// Built-in definition for the `document` kind (no extra properties).
  static let document = KindDefinition(kind: .document, properties: [])

  /// Built-in definition for the `issue` kind.
  static let issue = KindDefinition(
    kind: .issue,
    properties: ["status", "priority"],
  )
}
