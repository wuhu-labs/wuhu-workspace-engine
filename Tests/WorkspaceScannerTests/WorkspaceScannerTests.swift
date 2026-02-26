import Foundation
import Testing
import WorkspaceContracts
import WorkspaceEngine
import WorkspaceScanner

// MARK: - Frontmatter Parsing Tests

@Suite("FrontmatterParser")
struct FrontmatterParserTests {
  @Test("parses standard frontmatter")
  func parseStandardFrontmatter() {
    let content = """
    ---
    title: "My Document"
    kind: issue
    status: open
    ---

    # Body
    """

    let result = FrontmatterParser.parse(content)

    #expect(result.fields["title"] == "My Document")
    #expect(result.fields["kind"] == "issue")
    #expect(result.fields["status"] == "open")
    #expect(result.body.contains("# Body"))
  }

  @Test("returns empty fields for content without frontmatter")
  func parseNoFrontmatter() {
    let content = """
    # Just a Heading

    Some text without any frontmatter.
    """

    let result = FrontmatterParser.parse(content)

    #expect(result.fields.isEmpty)
    #expect(result.body == content)
  }

  @Test("handles empty frontmatter block")
  func parseEmptyFrontmatter() {
    let content = """
    ---
    ---

    # After Empty Frontmatter
    """

    let result = FrontmatterParser.parse(content)

    #expect(result.fields.isEmpty)
    #expect(result.body.contains("# After Empty Frontmatter"))
  }

  @Test("handles frontmatter with no closing delimiter")
  func parseUnclosedFrontmatter() {
    let content = """
    ---
    title: "Broken"
    kind: issue
    """

    let result = FrontmatterParser.parse(content)

    // No closing delimiter means no valid frontmatter.
    #expect(result.fields.isEmpty)
    #expect(result.body == content)
  }

  @Test("skips nested YAML structures")
  func parseNestedYAML() {
    let content = """
    ---
    title: "Has Nested"
    tags:
      - one
      - two
    status: open
    ---

    # Body
    """

    let result = FrontmatterParser.parse(content)

    #expect(result.fields["title"] == "Has Nested")
    #expect(result.fields["status"] == "open")
    // Nested array should be skipped.
    #expect(result.fields["tags"] == nil)
  }

  @Test("handles numeric and boolean values as strings")
  func parseNonStringValues() {
    let content = """
    ---
    title: "Numbers"
    count: 42
    enabled: true
    ---

    Body.
    """

    let result = FrontmatterParser.parse(content)

    #expect(result.fields["title"] == "Numbers")
    #expect(result.fields["count"] == "42")
    #expect(result.fields["enabled"] == "true")
  }

  @Test("frontmatter not at start is ignored")
  func parseFrontmatterNotAtStart() {
    let content = """
    Some text first.

    ---
    title: "Not Frontmatter"
    ---
    """

    let result = FrontmatterParser.parse(content)

    #expect(result.fields.isEmpty)
    #expect(result.body == content)
  }
}

// MARK: - Title Extraction Tests

@Suite("Title Extraction")
struct TitleExtractionTests {
  @Test("extracts title from first H1 heading")
  func extractH1Title() {
    let body = """

    # My Great Document

    Some content here.
    """

    let title = FrontmatterParser.extractHeadingTitle(from: body)
    #expect(title == "My Great Document")
  }

  @Test("returns nil when no heading is present")
  func extractNoHeading() {
    let body = """
    Just plain text.
    No headings here.
    """

    let title = FrontmatterParser.extractHeadingTitle(from: body)
    #expect(title == nil)
  }

  @Test("ignores H2 and deeper headings")
  func ignoreH2Headings() {
    let body = """
    ## This is H2

    ### This is H3

    Normal text.
    """

    let title = FrontmatterParser.extractHeadingTitle(from: body)
    #expect(title == nil)
  }

  @Test("takes the first H1 if there are multiple")
  func firstH1Wins() {
    let body = """
    # First Heading

    Some text.

    # Second Heading
    """

    let title = FrontmatterParser.extractHeadingTitle(from: body)
    #expect(title == "First Heading")
  }
}

// MARK: - WorkspaceScanner.parseContent Tests

@Suite("WorkspaceScanner.parseContent")
struct ParseContentTests {
  @Test("extracts kind, title, and properties from full frontmatter")
  func parseFullFrontmatter() {
    let content = """
    ---
    title: "Sample Issue"
    kind: issue
    status: open
    priority: high
    ---

    # Sample Issue
    """

    let (record, properties) = WorkspaceScanner.parseContent(content, path: "issues/001.md")

    #expect(record.path == "issues/001.md")
    #expect(record.kind == .issue)
    #expect(record.title == "Sample Issue")
    #expect(properties["status"] == "open")
    #expect(properties["priority"] == "high")
    // kind and title should not appear in properties.
    #expect(properties["kind"] == nil)
    #expect(properties["title"] == nil)
  }

  @Test("defaults kind to document when not specified")
  func defaultKind() {
    let content = """
    ---
    title: "A Plain Document"
    ---

    # A Plain Document
    """

    let (record, properties) = WorkspaceScanner.parseContent(content, path: "docs/plain.md")

    #expect(record.kind == .document)
    #expect(record.title == "A Plain Document")
    #expect(properties.isEmpty)
  }

  @Test("extracts title from heading when not in frontmatter")
  func titleFromHeading() {
    let content = """
    # Heading Title

    Some body text.
    """

    let (record, _) = WorkspaceScanner.parseContent(content, path: "notes/note.md")

    #expect(record.kind == .document)
    #expect(record.title == "Heading Title")
  }

  @Test("title is nil when neither frontmatter nor heading provides one")
  func noTitle() {
    let content = "Just plain text with no metadata at all."

    let (record, _) = WorkspaceScanner.parseContent(content, path: "orphan.md")

    #expect(record.kind == .document)
    #expect(record.title == nil)
  }
}

// MARK: - Configuration Loader Tests

@Suite("ConfigurationLoader")
struct ConfigurationLoaderTests {
  @Test("parses valid wuhu.yml")
  func parseValidConfig() throws {
    let yaml = """
    kinds:
      - kind: recipe
        properties:
          - cuisine
          - difficulty
          - servings
      - kind: project
        properties:
          - status
          - priority
          - owner
    """

    let config = try ConfigurationLoader.parseConfiguration(yaml)

    #expect(config.kinds.count == 2)

    let recipe = config.kinds.first { $0.kind == Kind(rawValue: "recipe") }
    #expect(recipe != nil)
    #expect(recipe?.properties == ["cuisine", "difficulty", "servings"])

    let project = config.kinds.first { $0.kind == Kind(rawValue: "project") }
    #expect(project != nil)
    #expect(project?.properties == ["status", "priority", "owner"])
  }

  @Test("returns empty config for empty YAML")
  func parseEmptyYAML() throws {
    let config = try ConfigurationLoader.parseConfiguration("")
    #expect(config.kinds.isEmpty)
  }

  @Test("returns empty config for YAML without kinds key")
  func parseNoKinds() throws {
    let yaml = """
    name: "My Workspace"
    version: 1
    """

    let config = try ConfigurationLoader.parseConfiguration(yaml)
    #expect(config.kinds.isEmpty)
  }

  @Test("handles kinds with no properties")
  func parseKindWithoutProperties() throws {
    let yaml = """
    kinds:
      - kind: note
    """

    let config = try ConfigurationLoader.parseConfiguration(yaml)
    #expect(config.kinds.count == 1)
    #expect(config.kinds[0].kind == Kind(rawValue: "note"))
    #expect(config.kinds[0].properties.isEmpty)
  }

  @Test("loads wuhu.yml from fixtures directory")
  func loadFromFixtures() throws {
    let fixturesURL = try #require(Bundle.module.resourceURL?.appendingPathComponent("Fixtures"))
    let config = try ConfigurationLoader.loadConfiguration(from: fixturesURL)

    #expect(config.kinds.count == 2)
  }

  @Test("returns empty config when wuhu.yml does not exist")
  func loadMissingConfig() throws {
    let tmpDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let config = try ConfigurationLoader.loadConfiguration(from: tmpDir)
    #expect(config == .empty)
  }
}

// MARK: - File Discovery Tests

@Suite("FileDiscovery")
struct FileDiscoveryTests {
  /// Creates a temporary directory structure for testing file discovery.
  private func makeTempWorkspace() throws -> URL {
    let tmpDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("workspace-scanner-test-\(UUID().uuidString)")
    let fm = FileManager.default

    // Create directory structure:
    // root/
    //   doc1.md
    //   notes/
    //     note1.md
    //     note2.md
    //   .hidden/
    //     secret.md
    //   node_modules/
    //     package.md
    //   .git/
    //     HEAD.md
    //   images/
    //     photo.png
    //   sub/
    //     deep/
    //       nested.md

    try fm.createDirectory(at: tmpDir.appendingPathComponent("notes"), withIntermediateDirectories: true)
    try fm.createDirectory(at: tmpDir.appendingPathComponent(".hidden"), withIntermediateDirectories: true)
    try fm.createDirectory(at: tmpDir.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
    try fm.createDirectory(at: tmpDir.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try fm.createDirectory(at: tmpDir.appendingPathComponent("images"), withIntermediateDirectories: true)
    try fm.createDirectory(at: tmpDir.appendingPathComponent("sub/deep"), withIntermediateDirectories: true)

    try "# Doc 1".write(to: tmpDir.appendingPathComponent("doc1.md"), atomically: true, encoding: .utf8)
    try "# Note 1".write(to: tmpDir.appendingPathComponent("notes/note1.md"), atomically: true, encoding: .utf8)
    try "# Note 2".write(to: tmpDir.appendingPathComponent("notes/note2.md"), atomically: true, encoding: .utf8)
    try "# Secret".write(to: tmpDir.appendingPathComponent(".hidden/secret.md"), atomically: true, encoding: .utf8)
    try "# Package".write(to: tmpDir.appendingPathComponent("node_modules/package.md"), atomically: true, encoding: .utf8)
    try "# HEAD".write(to: tmpDir.appendingPathComponent(".git/HEAD.md"), atomically: true, encoding: .utf8)
    try Data([0xFF]).write(to: tmpDir.appendingPathComponent("images/photo.png"))
    try "# Nested".write(to: tmpDir.appendingPathComponent("sub/deep/nested.md"), atomically: true, encoding: .utf8)

    return tmpDir
  }

  @Test("discovers .md files recursively")
  func discoverFiles() throws {
    let root = try makeTempWorkspace()
    defer { try? FileManager.default.removeItem(at: root) }

    let files = try FileDiscovery.discoverMarkdownFiles(in: root)
    let paths = files.map(\.relativePath)

    #expect(paths.contains("doc1.md"))
    #expect(paths.contains("notes/note1.md"))
    #expect(paths.contains("notes/note2.md"))
    #expect(paths.contains("sub/deep/nested.md"))
  }

  @Test("skips hidden directories")
  func skipHiddenDirs() throws {
    let root = try makeTempWorkspace()
    defer { try? FileManager.default.removeItem(at: root) }

    let files = try FileDiscovery.discoverMarkdownFiles(in: root)
    let paths = files.map(\.relativePath)

    #expect(!paths.contains(".hidden/secret.md"))
    #expect(!paths.contains(".git/HEAD.md"))
  }

  @Test("skips node_modules")
  func skipNodeModules() throws {
    let root = try makeTempWorkspace()
    defer { try? FileManager.default.removeItem(at: root) }

    let files = try FileDiscovery.discoverMarkdownFiles(in: root)
    let paths = files.map(\.relativePath)

    #expect(!paths.contains("node_modules/package.md"))
  }

  @Test("skips non-markdown files")
  func skipNonMarkdown() throws {
    let root = try makeTempWorkspace()
    defer { try? FileManager.default.removeItem(at: root) }

    let files = try FileDiscovery.discoverMarkdownFiles(in: root)
    let paths = files.map(\.relativePath)

    #expect(!paths.contains("images/photo.png"))
  }

  @Test("returns sorted results")
  func sortedResults() throws {
    let root = try makeTempWorkspace()
    defer { try? FileManager.default.removeItem(at: root) }

    let files = try FileDiscovery.discoverMarkdownFiles(in: root)
    let paths = files.map(\.relativePath)

    #expect(paths == paths.sorted())
  }

  @Test("returns empty array for empty directory")
  func emptyDirectory() throws {
    let tmpDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let files = try FileDiscovery.discoverMarkdownFiles(in: tmpDir)
    #expect(files.isEmpty)
  }
}

// MARK: - Full Scan Integration Tests

@Suite("WorkspaceScanner Integration")
struct WorkspaceScannerIntegrationTests {
  @Test("scans fixtures directory into engine")
  func scanFixtures() throws {
    let fixturesURL = try #require(Bundle.module.resourceURL?.appendingPathComponent("Fixtures"))
    let scanner = WorkspaceScanner(root: fixturesURL)
    let engine = try WorkspaceEngine()

    try scanner.scan(into: engine)

    let allDocs = try engine.allDocuments()

    // We have fixture files: sample-issue.md, plain-doc.md, no-heading.md,
    // heading-only.md, no-metadata.md, empty-frontmatter.md
    // (wuhu.yml is not a .md file so it's excluded)
    #expect(allDocs.count == 6)

    // Check sample-issue.md
    let issue = try engine.document(at: "sample-issue.md")
    #expect(issue != nil)
    #expect(issue?.record.kind == .issue)
    #expect(issue?.record.title == "Sample Issue")
    #expect(issue?.properties["status"] == "open")
    #expect(issue?.properties["priority"] == "high")

    // Check plain-doc.md
    let plain = try engine.document(at: "plain-doc.md")
    #expect(plain != nil)
    #expect(plain?.record.kind == .document)
    #expect(plain?.record.title == "A Plain Document")
  }

  @Test("scan clears existing documents")
  func scanClearsExisting() throws {
    let fixturesURL = try #require(Bundle.module.resourceURL?.appendingPathComponent("Fixtures"))
    let scanner = WorkspaceScanner(root: fixturesURL)
    let engine = try WorkspaceEngine()

    // Insert a document that doesn't exist on disk.
    let ghost = DocumentRecord(path: "ghost.md", kind: .document, title: "Ghost")
    try engine.upsertDocument(ghost)

    // Scan should clear the ghost.
    try scanner.scan(into: engine)

    let ghostDoc = try engine.document(at: "ghost.md")
    #expect(ghostDoc == nil)
  }

  @Test("heading-only fixture gets title from heading")
  func headingOnlyFixture() throws {
    let fixturesURL = try #require(Bundle.module.resourceURL?.appendingPathComponent("Fixtures"))
    let scanner = WorkspaceScanner(root: fixturesURL)
    let engine = try WorkspaceEngine()

    try scanner.scan(into: engine)

    let doc = try engine.document(at: "heading-only.md")
    #expect(doc != nil)
    #expect(doc?.record.title == "Heading Only Document")
    #expect(doc?.record.kind == .document)
  }

  @Test("no-metadata fixture has nil title")
  func noMetadataFixture() throws {
    let fixturesURL = try #require(Bundle.module.resourceURL?.appendingPathComponent("Fixtures"))
    let scanner = WorkspaceScanner(root: fixturesURL)
    let engine = try WorkspaceEngine()

    try scanner.scan(into: engine)

    let doc = try engine.document(at: "no-metadata.md")
    #expect(doc != nil)
    #expect(doc?.record.title == nil)
    #expect(doc?.record.kind == .document)
  }

  @Test("empty-frontmatter fixture gets title from heading")
  func emptyFrontmatterFixture() throws {
    let fixturesURL = try #require(Bundle.module.resourceURL?.appendingPathComponent("Fixtures"))
    let scanner = WorkspaceScanner(root: fixturesURL)
    let engine = try WorkspaceEngine()

    try scanner.scan(into: engine)

    let doc = try engine.document(at: "empty-frontmatter.md")
    #expect(doc != nil)
    #expect(doc?.record.title == "Empty Frontmatter")
    #expect(doc?.record.kind == .document)
  }

  @Test("no-heading fixture gets title from frontmatter")
  func noHeadingFixture() throws {
    let fixturesURL = try #require(Bundle.module.resourceURL?.appendingPathComponent("Fixtures"))
    let scanner = WorkspaceScanner(root: fixturesURL)
    let engine = try WorkspaceEngine()

    try scanner.scan(into: engine)

    let doc = try engine.document(at: "no-heading.md")
    #expect(doc != nil)
    #expect(doc?.record.title == "No Heading Doc")
    #expect(doc?.properties["custom_key"] == "custom_value")
  }

  @Test("loadConfiguration from fixtures")
  func loadConfiguration() throws {
    let fixturesURL = try #require(Bundle.module.resourceURL?.appendingPathComponent("Fixtures"))
    let scanner = WorkspaceScanner(root: fixturesURL)

    let config = try scanner.loadConfiguration()

    #expect(config.kinds.count == 2)

    let recipe = config.kinds.first { $0.kind == Kind(rawValue: "recipe") }
    #expect(recipe != nil)
    #expect(recipe?.properties == ["cuisine", "difficulty", "servings"])
  }

  @Test("discoverFiles from fixtures")
  func discoverFiles() throws {
    let fixturesURL = try #require(Bundle.module.resourceURL?.appendingPathComponent("Fixtures"))
    let scanner = WorkspaceScanner(root: fixturesURL)

    let files = try scanner.discoverFiles()

    // Should find all .md files but not wuhu.yml.
    let names = files.map(\.lastPathComponent).sorted()
    #expect(names.contains("sample-issue.md"))
    #expect(names.contains("plain-doc.md"))
    #expect(!names.contains("wuhu.yml"))
  }
}
