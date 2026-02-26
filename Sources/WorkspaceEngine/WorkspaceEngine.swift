// WorkspaceEngine — pure SQLite-backed query engine.
// No filesystem knowledge. Accepts updates, runs queries, provides observation.

import GRDB
import WorkspaceContracts

/// The pure query engine that owns the SQLite database.
///
/// `WorkspaceEngine` manages an in-memory (or file-backed) SQLite database via GRDB.
/// It creates the schema based on a ``WorkspaceConfiguration``, handles document CRUD,
/// runs queries, and exposes GRDB observation for reactive updates.
///
/// **This type has no filesystem knowledge.** Data is fed into it by an external scanner.
public final class WorkspaceEngine: Sendable {
  /// The underlying GRDB database queue.
  private let dbQueue: DatabaseQueue

  /// The kind definitions that were used to set up the schema.
  public let kindDefinitions: [KindDefinition]

  // MARK: - Initialization

  /// Creates a new engine with an **in-memory** database.
  ///
  /// - Parameter configuration: The workspace configuration describing known kinds.
  ///   Built-in kinds (document, issue) are always included.
  public init(configuration: WorkspaceConfiguration = .empty) throws {
    dbQueue = try DatabaseQueue()
    kindDefinitions = Self.resolvedKindDefinitions(from: configuration)
    try createSchema()
  }

  /// Creates a new engine with a **file-backed** database.
  ///
  /// - Parameters:
  ///   - path: The filesystem path for the SQLite database file.
  ///   - configuration: The workspace configuration describing known kinds.
  public init(path: String, configuration: WorkspaceConfiguration = .empty) throws {
    dbQueue = try DatabaseQueue(path: path)
    kindDefinitions = Self.resolvedKindDefinitions(from: configuration)
    try createSchema()
  }

  // MARK: - Schema

  /// Merges built-in kind definitions with any custom ones from the configuration.
  ///
  /// Custom definitions for built-in kinds (e.g., adding properties to `issue`)
  /// replace the built-in definition.
  private static func resolvedKindDefinitions(
    from configuration: WorkspaceConfiguration,
  ) -> [KindDefinition] {
    var definitionsByKind: [Kind: KindDefinition] = [:]

    // Start with built-ins.
    for builtIn in [KindDefinition.document, .issue] {
      definitionsByKind[builtIn.kind] = builtIn
    }

    // Overlay custom definitions.
    for custom in configuration.kinds {
      definitionsByKind[custom.kind] = custom
    }

    return Array(definitionsByKind.values)
  }

  /// Creates all tables: `docs`, `properties`, and one extension table per kind
  /// that has known properties.
  private func createSchema() throws {
    try dbQueue.write { db in
      // Enable foreign key support.
      try db.execute(sql: "PRAGMA foreign_keys = ON")

      // 1. docs table — universal registry.
      try db.execute(sql: """
        CREATE TABLE IF NOT EXISTS docs (
          path TEXT PRIMARY KEY,
          kind TEXT NOT NULL DEFAULT 'document',
          title TEXT
        )
      """)

      // 2. properties table — key-value catch-all.
      try db.execute(sql: """
        CREATE TABLE IF NOT EXISTS properties (
          path TEXT NOT NULL REFERENCES docs(path) ON DELETE CASCADE,
          key TEXT NOT NULL,
          value TEXT NOT NULL,
          PRIMARY KEY (path, key)
        )
      """)

      // 3. Kind-specific extension tables.
      for definition in self.kindDefinitions {
        guard !definition.properties.isEmpty else { continue }

        let tableName = Self.tableName(for: definition.kind)
        let columnDefs = definition.properties.map { "\($0) TEXT" }.joined(separator: ", ")

        try db.execute(sql: """
          CREATE TABLE IF NOT EXISTS \(tableName) (
            path TEXT PRIMARY KEY REFERENCES docs(path) ON DELETE CASCADE,
            \(columnDefs)
          )
        """)
      }
    }
  }

  /// Returns the extension table name for a kind (simple pluralization: kind + "s").
  static func tableName(for kind: Kind) -> String {
    kind.rawValue + "s"
  }

  // MARK: - Document CRUD

  /// Inserts or updates a document and its properties.
  ///
  /// - Parameters:
  ///   - record: The document record (path, kind, title).
  ///   - properties: All frontmatter properties as key-value pairs.
  public func upsertDocument(
    _ record: DocumentRecord,
    properties: [String: String] = [:],
  ) throws {
    try dbQueue.write { db in
      try db.execute(sql: "PRAGMA foreign_keys = ON")

      // Upsert into docs.
      try db.execute(
        sql: """
          INSERT INTO docs (path, kind, title)
          VALUES (?, ?, ?)
          ON CONFLICT(path) DO UPDATE SET kind = excluded.kind, title = excluded.title
        """,
        arguments: [record.path, record.kind.rawValue, record.title],
      )

      // Replace all properties for this path.
      try db.execute(
        sql: "DELETE FROM properties WHERE path = ?",
        arguments: [record.path],
      )

      for (key, value) in properties {
        try db.execute(
          sql: "INSERT INTO properties (path, key, value) VALUES (?, ?, ?)",
          arguments: [record.path, key, value],
        )
      }

      // Upsert into the kind extension table if it has known properties.
      if let definition = self.kindDefinitions.first(where: { $0.kind == record.kind }),
         !definition.properties.isEmpty
      {
        let tableName = Self.tableName(for: record.kind)
        let columns = ["path"] + definition.properties
        let placeholders = columns.map { _ in "?" }.joined(separator: ", ")
        let columnList = columns.joined(separator: ", ")

        let updateClauses = definition.properties
          .map { "\($0) = excluded.\($0)" }
          .joined(separator: ", ")

        var stmtArgs = StatementArguments()
        stmtArgs += [record.path]
        for prop in definition.properties {
          if let val = properties[prop] {
            stmtArgs += [val]
          } else {
            stmtArgs += [String?.none] // NULL
          }
        }

        try db.execute(
          sql: """
            INSERT INTO \(tableName) (\(columnList))
            VALUES (\(placeholders))
            ON CONFLICT(path) DO UPDATE SET \(updateClauses)
          """,
          arguments: stmtArgs,
        )
      }
    }
  }

  /// Removes a document and all its associated data (properties and kind extension rows
  /// are removed via CASCADE).
  ///
  /// - Parameter path: The workspace-relative path of the document to remove.
  public func removeDocument(at path: String) throws {
    try dbQueue.write { db in
      try db.execute(sql: "PRAGMA foreign_keys = ON")
      try db.execute(
        sql: "DELETE FROM docs WHERE path = ?",
        arguments: [path],
      )
    }
  }

  /// Removes all documents from the database.
  public func removeAllDocuments() throws {
    try dbQueue.write { db in
      try db.execute(sql: "PRAGMA foreign_keys = ON")
      try db.execute(sql: "DELETE FROM docs")
    }
  }

  // MARK: - Queries

  /// Returns all documents with their properties.
  public func allDocuments() throws -> [WorkspaceDocument] {
    try dbQueue.read { db in
      try self.fetchDocuments(db, sql: "SELECT * FROM docs ORDER BY path")
    }
  }

  /// Returns all documents of a given kind.
  ///
  /// - Parameter kind: The kind to filter by.
  public func documents(where kind: Kind) throws -> [WorkspaceDocument] {
    try dbQueue.read { db in
      try self.fetchDocuments(
        db,
        sql: "SELECT * FROM docs WHERE kind = ? ORDER BY path",
        arguments: [kind.rawValue],
      )
    }
  }

  /// Returns a single document by its path, or `nil` if not found.
  ///
  /// - Parameter path: The workspace-relative path.
  public func document(at path: String) throws -> WorkspaceDocument? {
    try dbQueue.read { db in
      let docs = try self.fetchDocuments(
        db,
        sql: "SELECT * FROM docs WHERE path = ?",
        arguments: [path],
      )
      return docs.first
    }
  }

  /// Executes arbitrary SQL and returns the results as an array of dictionaries.
  ///
  /// This is the escape hatch for ad-hoc queries. Each row is returned as a
  /// `[String: String]` dictionary where keys are column names and values are
  /// the string representation of column values (NULLs are omitted).
  ///
  /// - Parameter sql: The SQL to execute.
  public func rawQuery(_ sql: String) throws -> [[String: String]] {
    try dbQueue.read { db in
      let rows = try Row.fetchAll(db, sql: sql)
      return rows.map { row in
        var dict: [String: String] = [:]
        for (column, dbValue) in row {
          if let string: String = dbValue.failableConvert() {
            dict[column] = string
          }
        }
        return dict
      }
    }
  }

  /// Executes arbitrary SQL that modifies the database (INSERT, UPDATE, DELETE, etc.).
  ///
  /// - Parameter sql: The SQL to execute.
  public func rawExecute(_ sql: String) throws {
    try dbQueue.write { db in
      try db.execute(sql: sql)
    }
  }

  // MARK: - Observation

  /// Returns an `AsyncSequence` that emits all documents whenever any document
  /// table changes.
  ///
  /// Uses GRDB's `ValueObservation` under the hood. The observation tracks reads
  /// from `docs` and `properties`, so it automatically fires when those tables change.
  public func observeAllDocuments()
    -> AsyncValueObservation<[WorkspaceDocument]>
  {
    let observation = ValueObservation.tracking { [self] db -> [WorkspaceDocument] in
      try fetchDocuments(db, sql: "SELECT * FROM docs ORDER BY path")
    }
    return observation.values(in: dbQueue)
  }

  /// Returns an `AsyncSequence` that emits documents of a specific kind whenever
  /// the underlying tables change.
  ///
  /// - Parameter kind: The kind to filter by.
  public func observeDocuments(where kind: Kind)
    -> AsyncValueObservation<[WorkspaceDocument]>
  {
    let observation = ValueObservation.tracking { [self] db -> [WorkspaceDocument] in
      try fetchDocuments(
        db,
        sql: "SELECT * FROM docs WHERE kind = ? ORDER BY path",
        arguments: [kind.rawValue],
      )
    }
    return observation.values(in: dbQueue)
  }

  // MARK: - Internal Helpers

  /// Fetches documents from the given SQL and hydrates them with their properties.
  private func fetchDocuments(
    _ db: Database,
    sql: String,
    arguments: StatementArguments = StatementArguments(),
  ) throws -> [WorkspaceDocument] {
    let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)

    return try rows.map { row in
      let path: String = row["path"]
      let kindRaw: String = row["kind"]
      let title: String? = row["title"]

      let record = DocumentRecord(
        path: path,
        kind: Kind(rawValue: kindRaw),
        title: title,
      )

      // Fetch properties from the properties table.
      let propRows = try Row.fetchAll(
        db,
        sql: "SELECT key, value FROM properties WHERE path = ?",
        arguments: [path],
      )

      var properties: [String: String] = [:]
      for propRow in propRows {
        let key: String = propRow["key"]
        let value: String = propRow["value"]
        properties[key] = value
      }

      return WorkspaceDocument(record: record, properties: properties)
    }
  }
}

// MARK: - DatabaseValue Helpers

extension DatabaseValue {
  /// Attempts to convert a `DatabaseValue` to a specific type, returning `nil` on failure.
  func failableConvert<T: DatabaseValueConvertible>() -> T? {
    T.fromDatabaseValue(self)
  }
}
