/// The parsed shape of a workspace's `wuhu.yml` configuration file.
///
/// Contains kind definitions, path-based rules, and any workspace-level settings.
public struct WorkspaceConfiguration: Sendable, Hashable, Codable {
  /// Custom kind definitions declared in `wuhu.yml`.
  ///
  /// Built-in kinds (`document`, `issue`) are always available and don't need to
  /// be listed here — but they can be to extend their known properties.
  public var kinds: [KindDefinition]

  /// Path-based rules for assigning kinds to documents based on their path.
  ///
  /// Rules are evaluated in order. The first rule whose glob pattern matches a
  /// document's workspace-relative path determines the document's kind — but only
  /// if the document has no `kind` in its frontmatter. Frontmatter always takes
  /// precedence.
  public var rules: [Rule]

  public init(kinds: [KindDefinition] = [], rules: [Rule] = []) {
    self.kinds = kinds
    self.rules = rules
  }
}

public extension WorkspaceConfiguration {
  /// A configuration with no custom kinds or rules — only built-ins apply.
  static let empty = WorkspaceConfiguration()
}
