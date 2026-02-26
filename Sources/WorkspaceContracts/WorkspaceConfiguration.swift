/// The parsed shape of a workspace's `wuhu.yml` configuration file.
///
/// Contains kind definitions and any workspace-level settings.
public struct WorkspaceConfiguration: Sendable, Hashable, Codable {
  /// Custom kind definitions declared in `wuhu.yml`.
  ///
  /// Built-in kinds (`document`, `issue`) are always available and don't need to
  /// be listed here — but they can be to extend their known properties.
  public var kinds: [KindDefinition]

  public init(kinds: [KindDefinition] = []) {
    self.kinds = kinds
  }
}

public extension WorkspaceConfiguration {
  /// A configuration with no custom kinds — only built-ins apply.
  static let empty = WorkspaceConfiguration()
}
