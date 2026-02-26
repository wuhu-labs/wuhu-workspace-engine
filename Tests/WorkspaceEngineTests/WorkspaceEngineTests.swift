import Testing
import WorkspaceContracts
@testable import WorkspaceEngine

// MARK: - Schema Tests

@Suite("Schema Creation")
struct SchemaTests {
  @Test("Creates docs table with correct columns")
  func docsTableExists() throws {
    let engine = try WorkspaceEngine()

    let columns = try engine.rawQuery(
      "SELECT name FROM pragma_table_info('docs') ORDER BY cid",
    )

    let names = columns.map { $0["name"]! }
    #expect(names == ["path", "kind", "title"])
  }

  @Test("Creates properties table with correct columns")
  func propertiesTableExists() throws {
    let engine = try WorkspaceEngine()

    let columns = try engine.rawQuery(
      "SELECT name FROM pragma_table_info('properties') ORDER BY cid",
    )

    let names = columns.map { $0["name"]! }
    #expect(names == ["path", "key", "value"])
  }

  @Test("Creates issues extension table with correct columns")
  func issuesTableExists() throws {
    let engine = try WorkspaceEngine()

    let columns = try engine.rawQuery(
      "SELECT name FROM pragma_table_info('issues') ORDER BY cid",
    )

    let names = columns.map { $0["name"]! }
    #expect(names == ["path", "status", "priority"])
  }

  @Test("Does not create extension table for document kind (no properties)")
  func noDocumentsExtensionTable() throws {
    let engine = try WorkspaceEngine()

    let tables = try engine.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='documents'",
    )

    #expect(tables.isEmpty)
  }

  @Test("Creates custom kind extension table")
  func customKindTable() throws {
    let customKind = KindDefinition(
      kind: Kind(rawValue: "recipe"),
      properties: ["cuisine", "difficulty", "servings"],
    )
    let config = WorkspaceConfiguration(kinds: [customKind])
    let engine = try WorkspaceEngine(configuration: config)

    let columns = try engine.rawQuery(
      "SELECT name FROM pragma_table_info('recipes') ORDER BY cid",
    )

    let names = columns.map { $0["name"]! }
    #expect(names == ["path", "cuisine", "difficulty", "servings"])
  }
}

// MARK: - Document CRUD Tests

@Suite("Document CRUD")
struct DocumentCRUDTests {
  @Test("Upsert inserts a new document")
  func upsertInsert() throws {
    let engine = try WorkspaceEngine()

    let record = DocumentRecord(path: "docs/hello.md", kind: .document, title: "Hello")
    try engine.upsertDocument(record)

    let doc = try engine.document(at: "docs/hello.md")
    #expect(doc != nil)
    #expect(doc?.record.path == "docs/hello.md")
    #expect(doc?.record.kind == .document)
    #expect(doc?.record.title == "Hello")
  }

  @Test("Upsert updates an existing document")
  func upsertUpdate() throws {
    let engine = try WorkspaceEngine()

    let record1 = DocumentRecord(path: "docs/hello.md", kind: .document, title: "Hello")
    try engine.upsertDocument(record1)

    let record2 = DocumentRecord(path: "docs/hello.md", kind: .document, title: "Updated")
    try engine.upsertDocument(record2)

    let doc = try engine.document(at: "docs/hello.md")
    #expect(doc?.record.title == "Updated")

    // Should still be one document, not two.
    let all = try engine.allDocuments()
    #expect(all.count == 1)
  }

  @Test("Upsert with properties stores them in properties table")
  func upsertWithProperties() throws {
    let engine = try WorkspaceEngine()

    let record = DocumentRecord(path: "issues/0001.md", kind: .issue, title: "Bug")
    try engine.upsertDocument(record, properties: [
      "status": "open",
      "priority": "high",
      "assignee": "alice",
    ])

    let doc = try engine.document(at: "issues/0001.md")
    #expect(doc?.properties["status"] == "open")
    #expect(doc?.properties["priority"] == "high")
    #expect(doc?.properties["assignee"] == "alice")
  }

  @Test("Upsert replaces old properties")
  func upsertReplacesProperties() throws {
    let engine = try WorkspaceEngine()

    let record = DocumentRecord(path: "issues/0001.md", kind: .issue, title: "Bug")
    try engine.upsertDocument(record, properties: [
      "status": "open",
      "priority": "high",
      "assignee": "alice",
    ])

    // Update with different properties.
    try engine.upsertDocument(record, properties: [
      "status": "closed",
    ])

    let doc = try engine.document(at: "issues/0001.md")
    #expect(doc?.properties["status"] == "closed")
    #expect(doc?.properties["priority"] == nil)
    #expect(doc?.properties["assignee"] == nil)
  }

  @Test("Upsert populates kind extension table")
  func upsertPopulatesExtensionTable() throws {
    let engine = try WorkspaceEngine()

    let record = DocumentRecord(path: "issues/0001.md", kind: .issue, title: "Bug")
    try engine.upsertDocument(record, properties: [
      "status": "open",
      "priority": "high",
      "assignee": "alice",
    ])

    // Query the extension table directly.
    let rows = try engine.rawQuery(
      "SELECT * FROM issues WHERE path = 'issues/0001.md'",
    )

    #expect(rows.count == 1)
    #expect(rows[0]["status"] == "open")
    #expect(rows[0]["priority"] == "high")
    // "assignee" is not a known issue property, so it should NOT be in the issues table.
    #expect(rows[0]["assignee"] == nil)
  }

  @Test("Remove document deletes from docs")
  func removeDocument() throws {
    let engine = try WorkspaceEngine()

    let record = DocumentRecord(path: "docs/hello.md", kind: .document, title: "Hello")
    try engine.upsertDocument(record, properties: ["tag": "greeting"])

    try engine.removeDocument(at: "docs/hello.md")

    let doc = try engine.document(at: "docs/hello.md")
    #expect(doc == nil)
  }

  @Test("Remove document cascades to properties")
  func removeDocumentCascadesProperties() throws {
    let engine = try WorkspaceEngine()

    let record = DocumentRecord(path: "issues/0001.md", kind: .issue, title: "Bug")
    try engine.upsertDocument(record, properties: ["status": "open"])

    try engine.removeDocument(at: "issues/0001.md")

    let propRows = try engine.rawQuery(
      "SELECT * FROM properties WHERE path = 'issues/0001.md'",
    )
    #expect(propRows.isEmpty)
  }

  @Test("Remove document cascades to kind extension table")
  func removeDocumentCascadesExtension() throws {
    let engine = try WorkspaceEngine()

    let record = DocumentRecord(path: "issues/0001.md", kind: .issue, title: "Bug")
    try engine.upsertDocument(record, properties: ["status": "open"])

    try engine.removeDocument(at: "issues/0001.md")

    let issueRows = try engine.rawQuery(
      "SELECT * FROM issues WHERE path = 'issues/0001.md'",
    )
    #expect(issueRows.isEmpty)
  }

  @Test("Remove all documents clears everything")
  func removeAllDocuments() throws {
    let engine = try WorkspaceEngine()

    for i in 1 ... 5 {
      let record = DocumentRecord(
        path: "docs/\(i).md",
        kind: .document,
        title: "Doc \(i)",
      )
      try engine.upsertDocument(record, properties: ["index": "\(i)"])
    }

    try engine.removeAllDocuments()

    let all = try engine.allDocuments()
    #expect(all.isEmpty)

    let propRows = try engine.rawQuery("SELECT * FROM properties")
    #expect(propRows.isEmpty)
  }

  @Test("Document with nil title")
  func nilTitle() throws {
    let engine = try WorkspaceEngine()

    let record = DocumentRecord(path: "docs/untitled.md", kind: .document)
    try engine.upsertDocument(record)

    let doc = try engine.document(at: "docs/untitled.md")
    #expect(doc != nil)
    #expect(doc?.record.title == nil)
  }
}

// MARK: - Query Tests

@Suite("Queries")
struct QueryTests {
  @Test("All documents returns all")
  func allDocuments() throws {
    let engine = try WorkspaceEngine()

    try engine.upsertDocument(DocumentRecord(path: "a.md", kind: .document, title: "A"))
    try engine.upsertDocument(DocumentRecord(path: "b.md", kind: .issue, title: "B"))
    try engine.upsertDocument(DocumentRecord(path: "c.md", kind: .document, title: "C"))

    let all = try engine.allDocuments()
    #expect(all.count == 3)
  }

  @Test("All documents are sorted by path")
  func allDocumentsSorted() throws {
    let engine = try WorkspaceEngine()

    try engine.upsertDocument(DocumentRecord(path: "c.md", kind: .document, title: "C"))
    try engine.upsertDocument(DocumentRecord(path: "a.md", kind: .document, title: "A"))
    try engine.upsertDocument(DocumentRecord(path: "b.md", kind: .document, title: "B"))

    let all = try engine.allDocuments()
    #expect(all.map(\.path) == ["a.md", "b.md", "c.md"])
  }

  @Test("Documents filtered by kind")
  func documentsByKind() throws {
    let engine = try WorkspaceEngine()

    try engine.upsertDocument(DocumentRecord(path: "doc1.md", kind: .document, title: "D1"))
    try engine.upsertDocument(DocumentRecord(path: "issue1.md", kind: .issue, title: "I1"))
    try engine.upsertDocument(DocumentRecord(path: "doc2.md", kind: .document, title: "D2"))
    try engine.upsertDocument(DocumentRecord(path: "issue2.md", kind: .issue, title: "I2"))

    let docs = try engine.documents(where: .document)
    #expect(docs.count == 2)
    #expect(docs.allSatisfy { $0.kind == .document })

    let issues = try engine.documents(where: .issue)
    #expect(issues.count == 2)
    #expect(issues.allSatisfy { $0.kind == .issue })
  }

  @Test("Document at path returns single result")
  func documentAtPath() throws {
    let engine = try WorkspaceEngine()

    try engine.upsertDocument(DocumentRecord(path: "target.md", kind: .document, title: "Target"))
    try engine.upsertDocument(DocumentRecord(path: "other.md", kind: .document, title: "Other"))

    let doc = try engine.document(at: "target.md")
    #expect(doc?.record.path == "target.md")
    #expect(doc?.record.title == "Target")
  }

  @Test("Document at nonexistent path returns nil")
  func documentAtNonexistentPath() throws {
    let engine = try WorkspaceEngine()

    let doc = try engine.document(at: "nonexistent.md")
    #expect(doc == nil)
  }

  @Test("Raw query works")
  func rawQuery() throws {
    let engine = try WorkspaceEngine()

    try engine.upsertDocument(
      DocumentRecord(path: "issues/0001.md", kind: .issue, title: "Bug"),
      properties: ["status": "open", "priority": "high"],
    )
    try engine.upsertDocument(
      DocumentRecord(path: "issues/0002.md", kind: .issue, title: "Feature"),
      properties: ["status": "closed", "priority": "low"],
    )

    let rows = try engine.rawQuery(
      "SELECT d.path, d.title, i.status FROM docs d JOIN issues i ON d.path = i.path WHERE i.status = 'open'",
    )

    #expect(rows.count == 1)
    #expect(rows[0]["title"] == "Bug")
    #expect(rows[0]["status"] == "open")
  }

  @Test("Raw query with join on properties table")
  func rawQueryProperties() throws {
    let engine = try WorkspaceEngine()

    try engine.upsertDocument(
      DocumentRecord(path: "docs/a.md", kind: .document, title: "A"),
      properties: ["tag": "important"],
    )
    try engine.upsertDocument(
      DocumentRecord(path: "docs/b.md", kind: .document, title: "B"),
      properties: ["tag": "trivial"],
    )

    let rows = try engine.rawQuery(
      "SELECT d.path FROM docs d JOIN properties p ON d.path = p.path WHERE p.key = 'tag' AND p.value = 'important'",
    )

    #expect(rows.count == 1)
    #expect(rows[0]["path"] == "docs/a.md")
  }
}

// MARK: - Multiple Kind Definitions

@Suite("Multiple Kind Definitions")
struct MultipleKindTests {
  @Test("Multiple custom kinds create separate extension tables")
  func multipleCustomKinds() throws {
    let config = WorkspaceConfiguration(kinds: [
      KindDefinition(kind: "recipe", properties: ["cuisine", "difficulty"]),
      KindDefinition(kind: "note", properties: ["category"]),
    ])
    let engine = try WorkspaceEngine(configuration: config)

    // Verify both extension tables exist.
    let recipeColumns = try engine.rawQuery(
      "SELECT name FROM pragma_table_info('recipes') ORDER BY cid",
    )
    #expect(recipeColumns.map { $0["name"]! } == ["path", "cuisine", "difficulty"])

    let noteColumns = try engine.rawQuery(
      "SELECT name FROM pragma_table_info('notes') ORDER BY cid",
    )
    #expect(noteColumns.map { $0["name"]! } == ["path", "category"])
  }

  @Test("Custom kind documents get populated extension table")
  func customKindPopulation() throws {
    let config = WorkspaceConfiguration(kinds: [
      KindDefinition(kind: "recipe", properties: ["cuisine", "difficulty"]),
    ])
    let engine = try WorkspaceEngine(configuration: config)

    try engine.upsertDocument(
      DocumentRecord(path: "recipes/pasta.md", kind: "recipe", title: "Pasta"),
      properties: ["cuisine": "Italian", "difficulty": "easy", "servings": "4"],
    )

    // Extension table should have cuisine and difficulty.
    let rows = try engine.rawQuery("SELECT * FROM recipes")
    #expect(rows.count == 1)
    #expect(rows[0]["cuisine"] == "Italian")
    #expect(rows[0]["difficulty"] == "easy")

    // Properties table should have all three.
    let props = try engine.rawQuery(
      "SELECT key, value FROM properties WHERE path = 'recipes/pasta.md' ORDER BY key",
    )
    #expect(props.count == 3)

    // Full document should return all properties.
    let doc = try engine.document(at: "recipes/pasta.md")
    #expect(doc?.properties["cuisine"] == "Italian")
    #expect(doc?.properties["difficulty"] == "easy")
    #expect(doc?.properties["servings"] == "4")
  }

  @Test("Built-in and custom kinds work together")
  func builtInAndCustom() throws {
    let config = WorkspaceConfiguration(kinds: [
      KindDefinition(kind: "recipe", properties: ["cuisine"]),
    ])
    let engine = try WorkspaceEngine(configuration: config)

    try engine.upsertDocument(
      DocumentRecord(path: "issues/1.md", kind: .issue, title: "Bug"),
      properties: ["status": "open"],
    )
    try engine.upsertDocument(
      DocumentRecord(path: "recipes/pasta.md", kind: "recipe", title: "Pasta"),
      properties: ["cuisine": "Italian"],
    )
    try engine.upsertDocument(
      DocumentRecord(path: "docs/readme.md", kind: .document, title: "README"),
    )

    let all = try engine.allDocuments()
    #expect(all.count == 3)

    let issues = try engine.documents(where: .issue)
    #expect(issues.count == 1)

    let recipes = try engine.documents(where: "recipe")
    #expect(recipes.count == 1)
  }
}

// MARK: - Edge Cases

@Suite("Edge Cases")
struct EdgeCaseTests {
  @Test("Empty database returns empty results")
  func emptyDatabase() throws {
    let engine = try WorkspaceEngine()

    let all = try engine.allDocuments()
    #expect(all.isEmpty)

    let doc = try engine.document(at: "anything.md")
    #expect(doc == nil)

    let docs = try engine.documents(where: .document)
    #expect(docs.isEmpty)
  }

  @Test("Document with empty properties dictionary")
  func emptyProperties() throws {
    let engine = try WorkspaceEngine()

    try engine.upsertDocument(
      DocumentRecord(path: "test.md", kind: .document, title: "Test"),
      properties: [:],
    )

    let doc = try engine.document(at: "test.md")
    #expect(doc?.properties.isEmpty == true)
  }

  @Test("Upsert changes document kind")
  func changeKind() throws {
    let engine = try WorkspaceEngine()

    // Insert as document.
    try engine.upsertDocument(
      DocumentRecord(path: "flexible.md", kind: .document, title: "Flexible"),
    )

    // Update to issue with properties.
    try engine.upsertDocument(
      DocumentRecord(path: "flexible.md", kind: .issue, title: "Now an issue"),
      properties: ["status": "open"],
    )

    let doc = try engine.document(at: "flexible.md")
    #expect(doc?.kind == .issue)
    #expect(doc?.title == "Now an issue")
    #expect(doc?.properties["status"] == "open")
  }

  @Test("Kind definition resolved correctly merges built-ins")
  func kindDefinitionResolution() throws {
    // Override the built-in issue kind with extra properties.
    let config = WorkspaceConfiguration(kinds: [
      KindDefinition(kind: .issue, properties: ["status", "priority", "assignee"]),
    ])
    let engine = try WorkspaceEngine(configuration: config)

    let columns = try engine.rawQuery(
      "SELECT name FROM pragma_table_info('issues') ORDER BY cid",
    )

    let names = columns.map { $0["name"]! }
    #expect(names == ["path", "status", "priority", "assignee"])
  }

  @Test("Extension table gets NULL for missing properties")
  func extensionTableNullProperties() throws {
    let engine = try WorkspaceEngine()

    // Insert issue with only status, no priority.
    try engine.upsertDocument(
      DocumentRecord(path: "issues/1.md", kind: .issue, title: "Partial"),
      properties: ["status": "open"],
    )

    let rows = try engine.rawQuery("SELECT status, priority FROM issues")
    #expect(rows.count == 1)
    #expect(rows[0]["status"] == "open")
    // priority should be NULL, which means absent from the dictionary.
    #expect(rows[0]["priority"] == nil)
  }
}
