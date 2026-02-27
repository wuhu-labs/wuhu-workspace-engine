// WorkspaceScanner — wuhu.yml configuration loading.

import Foundation
import WorkspaceContracts
import Yams

/// Loads workspace configuration from `wuhu.yml`.
public enum ConfigurationLoader {
  /// Loads and parses `wuhu.yml` from the given workspace root.
  ///
  /// If the file doesn't exist, returns ``WorkspaceConfiguration.empty``.
  /// If the file exists but is empty or has no `kinds` key, returns an empty
  /// configuration.
  ///
  /// - Parameter root: The root URL of the workspace directory.
  /// - Returns: The parsed workspace configuration.
  public static func loadConfiguration(from root: URL) throws -> WorkspaceConfiguration {
    let configURL = root.appendingPathComponent("wuhu.yml")

    guard FileManager.default.fileExists(atPath: configURL.path) else {
      return .empty
    }

    let content = try String(contentsOf: configURL, encoding: .utf8)
    return try parseConfiguration(content)
  }

  /// Parses a YAML string into a ``WorkspaceConfiguration``.
  ///
  /// Expected format:
  /// ```yaml
  /// kinds:
  ///   - kind: recipe
  ///     properties:
  ///       - cuisine
  ///       - difficulty
  /// rules:
  ///   - path: "issues/**"
  ///     kind: issue
  ///   - path: "docs/architecture/**"
  ///     kind: architecture
  /// ```
  public static func parseConfiguration(_ yaml: String) throws -> WorkspaceConfiguration {
    guard !yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return .empty
    }

    guard let parsed = try Yams.load(yaml: yaml) else {
      return .empty
    }

    guard let dict = parsed as? [String: Any] else {
      return .empty
    }

    let definitions = parseKinds(from: dict)
    let rules = parseRules(from: dict)

    return WorkspaceConfiguration(kinds: definitions, rules: rules)
  }

  /// Parses the `kinds` section from the top-level YAML dictionary.
  private static func parseKinds(from dict: [String: Any]) -> [KindDefinition] {
    guard let kindsArray = dict["kinds"] as? [[String: Any]] else {
      return []
    }

    var definitions: [KindDefinition] = []

    for kindDict in kindsArray {
      guard let kindName = kindDict["kind"] as? String else {
        continue
      }

      let properties: [String] = if let propsArray = kindDict["properties"] as? [String] {
        propsArray
      } else {
        []
      }

      let definition = KindDefinition(
        kind: Kind(rawValue: kindName),
        properties: properties,
      )
      definitions.append(definition)
    }

    return definitions
  }

  /// Parses the `rules` section from the top-level YAML dictionary.
  private static func parseRules(from dict: [String: Any]) -> [Rule] {
    guard let rulesArray = dict["rules"] as? [[String: Any]] else {
      return []
    }

    var rules: [Rule] = []

    for ruleDict in rulesArray {
      guard let pathPattern = ruleDict["path"] as? String,
            let kindName = ruleDict["kind"] as? String
      else {
        continue
      }

      let rule = Rule(
        path: pathPattern,
        kind: Kind(rawValue: kindName),
      )
      rules.append(rule)
    }

    return rules
  }
}
