// WorkspaceScanner — filesystem watching (FSEvents on macOS, inotify on Linux).

import Foundation

// MARK: - FileWatchEvent

/// Events emitted by the file watcher.
public enum FileWatchEvent: Sendable, Equatable {
  /// A new file appeared at the given workspace-relative path.
  case created(path: String)

  /// An existing file was modified at the given workspace-relative path.
  case modified(path: String)

  /// A file was removed at the given workspace-relative path.
  case deleted(path: String)

  /// A full rescan is required (e.g., overflow, root renamed, etc.).
  case scanRequired
}

// MARK: - Locked

/// A simple lock-protected box. Used to store mutable state inside `Sendable` types
/// without requiring `Mutex` (which needs macOS 15+).
private final class Locked<Value>: @unchecked Sendable {
  private let _lock = NSLock()
  private var _value: Value

  init(_ value: Value) {
    _value = value
  }

  func withLock<T>(_ body: (inout Value) throws -> T) rethrows -> T {
    _lock.lock()
    defer { _lock.unlock() }
    return try body(&_value)
  }
}

// MARK: - FileWatcher

/// Watches a directory tree for filesystem changes.
///
/// On macOS, uses FSEvents (CoreServices). On Linux, uses inotify.
/// Returns an ``AsyncStream`` of ``FileWatchEvent`` values.
///
/// The watcher is designed to be started once and stopped when no longer needed.
/// Starting creates a background monitoring loop; stopping tears it down.
public final class FileWatcher: @unchecked Sendable {
  /// The root directory being watched.
  public let root: URL

  /// The continuation for the current event stream.
  private let _continuation = Locked<AsyncStream<FileWatchEvent>.Continuation?>(nil)

  #if os(macOS)
    /// FSEvents stream reference.
    private let _streamRef = Locked<OpaquePointer?>(nil)
    /// Retained context pointer for the FSEvents callback.
    private let _contextPtr = Locked<UnsafeMutableRawPointer?>(nil)
  #elseif os(Linux)
    /// The inotify context managing the polling loop.
    private let _inotifyCtx = Locked<AnyObject?>(nil)
  #endif

  /// Creates a file watcher for the given root directory.
  ///
  /// - Parameter root: The root directory to watch recursively.
  public init(root: URL) {
    // Resolve symlinks so the root path matches what the OS reports in events.
    // On macOS, FSEvents reports paths from realpath(3) (e.g., /private/var/...)
    // while Foundation URLs may use symlinks (e.g., /var/...).
    // URL.resolvingSymlinksInPath() doesn't resolve firmlinks like /var → /private/var,
    // so we use realpath(3) directly.
    self.root = Self.resolvedURL(root)
  }

  /// Resolves a URL to its real path using realpath(3), falling back to
  /// `standardizedFileURL` if the path doesn't exist yet.
  private static func resolvedURL(_ url: URL) -> URL {
    let path = url.path
    var resolved = [CChar](repeating: 0, count: Int(PATH_MAX))
    if let real = realpath(path, &resolved) {
      return URL(fileURLWithPath: String(cString: real))
    }
    return url.standardizedFileURL
  }

  /// Starts watching the directory tree for changes.
  ///
  /// Returns an `AsyncStream` of events. The stream ends when ``stop()`` is
  /// called or the watcher is deallocated.
  ///
  /// Only one stream can be active at a time. Calling `start()` again while
  /// already watching will stop the previous watcher first.
  public func start() -> AsyncStream<FileWatchEvent> {
    // Stop any previous watcher.
    stop()

    let (stream, continuation) = AsyncStream<FileWatchEvent>.makeStream()
    continuation.onTermination = { [weak self] _ in
      self?.stop()
    }

    _continuation.withLock { $0 = continuation }

    #if os(macOS)
      startFSEvents(continuation: continuation)
    #elseif os(Linux)
      startInotify(continuation: continuation)
    #else
      continuation.finish()
    #endif

    return stream
  }

  /// Stops watching and cleans up all resources.
  public func stop() {
    #if os(macOS)
      stopFSEvents()
    #elseif os(Linux)
      stopInotify()
    #endif

    let cont: AsyncStream<FileWatchEvent>.Continuation? = _continuation.withLock { c in
      let old = c
      c = nil
      return old
    }
    cont?.finish()
  }

  deinit {
    stop()
  }

  // MARK: - Path Helpers

  /// Converts an absolute path to a workspace-relative path.
  func relativePath(for absolutePath: String) -> String {
    let rootPath = root.path
    let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
    if absolutePath.hasPrefix(prefix) {
      return String(absolutePath.dropFirst(prefix.count))
    }
    return absolutePath
  }

  /// Returns whether a path component should be skipped during watching.
  static func shouldSkip(_ component: String) -> Bool {
    component.hasPrefix(".") ||
      component == "node_modules" ||
      component == ".build" ||
      component == ".git"
  }

  /// Returns whether a relative path contains any skippable components.
  static func shouldSkipPath(_ relativePath: String) -> Bool {
    let components = relativePath.split(separator: "/").map(String.init)
    return components.contains(where: shouldSkip)
  }
}

// MARK: - macOS FSEvents Implementation

#if os(macOS)

  import CoreServices

  /// Context object passed into the FSEvents callback via the info pointer.
  private final class FSEventsContext {
    weak var watcher: FileWatcher?
    let continuation: AsyncStream<FileWatchEvent>.Continuation

    init(watcher: FileWatcher, continuation: AsyncStream<FileWatchEvent>.Continuation) {
      self.watcher = watcher
      self.continuation = continuation
    }
  }

  extension FileWatcher {
    func startFSEvents(continuation: AsyncStream<FileWatchEvent>.Continuation) {
      let rootPath = root.path as CFString
      let pathsToWatch = [rootPath] as CFArray

      let context = FSEventsContext(watcher: self, continuation: continuation)
      let contextPtr = Unmanaged.passRetained(context).toOpaque()

      var fsContext = FSEventStreamContext(
        version: 0,
        info: contextPtr,
        retain: nil,
        release: nil,
        copyDescription: nil,
      )

      let flags: FSEventStreamCreateFlags =
        UInt32(kFSEventStreamCreateFlagUseCFTypes) |
        UInt32(kFSEventStreamCreateFlagFileEvents) |
        UInt32(kFSEventStreamCreateFlagNoDefer)

      guard let stream = FSEventStreamCreate(
        nil,
        fsEventsCallback,
        &fsContext,
        pathsToWatch,
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
        0.1, // 100ms latency
        flags,
      ) else {
        Unmanaged<FSEventsContext>.fromOpaque(contextPtr).release()
        continuation.finish()
        return
      }

      let queue = DispatchQueue(label: "com.wuhu.filewatcher.fsevents", qos: .utility)
      FSEventStreamSetDispatchQueue(stream, queue)
      FSEventStreamStart(stream)

      _streamRef.withLock { $0 = stream }
      _contextPtr.withLock { $0 = contextPtr }
    }

    func stopFSEvents() {
      let stream: OpaquePointer? = _streamRef.withLock { s in
        let old = s
        s = nil
        return old
      }
      let ctxPtr: UnsafeMutableRawPointer? = _contextPtr.withLock { p in
        let old = p
        p = nil
        return old
      }

      if let stream {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
      }
      if let ctxPtr {
        Unmanaged<FSEventsContext>.fromOpaque(ctxPtr).release()
      }
    }
  }

  /// The C callback for FSEvents.
  private func fsEventsCallback(
    _: ConstFSEventStreamRef,
    _ clientCallBackInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _: UnsafePointer<FSEventStreamEventId>,
  ) {
    guard let clientCallBackInfo else { return }
    let context = Unmanaged<FSEventsContext>.fromOpaque(clientCallBackInfo)
      .takeUnretainedValue()
    guard let watcher = context.watcher else { return }

    let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()

    for i in 0 ..< numEvents {
      let flags = eventFlags[i]

      // Check for must-scan-subdirs (overflow / kernel dropped events).
      if flags & UInt32(kFSEventStreamEventFlagMustScanSubDirs) != 0 {
        context.continuation.yield(.scanRequired)
        continue
      }

      // Check for root changed.
      if flags & UInt32(kFSEventStreamEventFlagRootChanged) != 0 {
        context.continuation.yield(.scanRequired)
        continue
      }

      // Get the path.
      guard let cfPath = CFArrayGetValueAtIndex(paths, i) else { continue }
      let path = Unmanaged<CFString>.fromOpaque(cfPath).takeUnretainedValue() as String

      let relativePath = watcher.relativePath(for: path)

      // Skip hidden/ignored paths.
      if FileWatcher.shouldSkipPath(relativePath) { continue }

      // Determine event type from flags.
      let isFile = flags & UInt32(kFSEventStreamEventFlagItemIsFile) != 0
      let isDir = flags & UInt32(kFSEventStreamEventFlagItemIsDir) != 0

      // We only care about file events for document tracking.
      guard isFile || (!isDir && !isFile) else { continue }

      let created = flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0
      let removed = flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0
      let modified = flags & UInt32(kFSEventStreamEventFlagItemModified) != 0
      let renamed = flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0

      if removed {
        if !FileManager.default.fileExists(atPath: path) {
          context.continuation.yield(.deleted(path: relativePath))
        } else {
          context.continuation.yield(.modified(path: relativePath))
        }
      } else if renamed {
        if FileManager.default.fileExists(atPath: path) {
          context.continuation.yield(.created(path: relativePath))
        } else {
          context.continuation.yield(.deleted(path: relativePath))
        }
      } else if created {
        context.continuation.yield(.created(path: relativePath))
      } else if modified {
        context.continuation.yield(.modified(path: relativePath))
      }
    }
  }

#endif

// MARK: - Linux inotify Implementation

#if os(Linux)

  import Glibc

  /// Context for the inotify polling loop.
  ///
  /// `@unchecked Sendable` because the mutable state (_running, _watchDescriptors)
  /// is protected by an `NSLock`, and the fd/pipe handles are only mutated in `stop()`.
  private final class InotifyContext: @unchecked Sendable {
    weak var watcher: FileWatcher?
    let continuation: AsyncStream<FileWatchEvent>.Continuation
    let fd: Int32

    private let _lock = NSLock()
    private var _running = true
    private var _watchDescriptors: [Int32: String] = [:]

    // Pipe for signaling stop.
    let stopPipeRead: Int32
    let stopPipeWrite: Int32

    var isRunning: Bool {
      _lock.lock()
      defer { _lock.unlock() }
      return _running
    }

    init(
      watcher: FileWatcher,
      continuation: AsyncStream<FileWatchEvent>.Continuation,
      fd: Int32,
    ) {
      self.watcher = watcher
      self.continuation = continuation
      self.fd = fd

      var pipeFds: [Int32] = [0, 0]
      pipe(&pipeFds)
      stopPipeRead = pipeFds[0]
      stopPipeWrite = pipeFds[1]
    }

    /// Add inotify watches for a directory and all its subdirectories.
    func addWatchesRecursively(at path: String) {
      let mask =
        UInt32(IN_CREATE) |
        UInt32(IN_MODIFY) |
        UInt32(IN_DELETE) |
        UInt32(IN_MOVED_FROM) |
        UInt32(IN_MOVED_TO) |
        UInt32(IN_ATTRIB)

      let wd = inotify_add_watch(fd, path, mask)
      if wd >= 0 {
        _lock.lock()
        _watchDescriptors[wd] = path
        _lock.unlock()
      }

      let fm = FileManager.default
      guard let contents = try? fm.contentsOfDirectory(atPath: path) else { return }

      for item in contents {
        if FileWatcher.shouldSkip(item) { continue }

        let fullPath = path + "/" + item
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue {
          addWatchesRecursively(at: fullPath)
        }
      }
    }

    /// The main polling loop. Runs on a background thread.
    func pollLoop() {
      let bufferSize = 4096
      let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 1)
      defer { buffer.deallocate() }

      while isRunning {
        var fds = [
          pollfd(fd: fd, events: Int16(POLLIN), revents: 0),
          pollfd(fd: stopPipeRead, events: Int16(POLLIN), revents: 0),
        ]

        let ret = poll(&fds, 2, 200)
        if ret < 0 {
          if errno == EINTR { continue }
          break
        }
        if ret == 0 { continue }

        // Check stop signal.
        if fds[1].revents & Int16(POLLIN) != 0 { break }

        // Read inotify events.
        if fds[0].revents & Int16(POLLIN) != 0 {
          let bytesRead = Glibc.read(fd, buffer, bufferSize)
          if bytesRead <= 0 { continue }

          var offset = 0
          while offset < bytesRead {
            let event = buffer.advanced(by: offset)
              .assumingMemoryBound(to: inotify_event.self).pointee
            let nameLength = Int(event.len)

            if event.mask & UInt32(IN_Q_OVERFLOW) != 0 {
              continuation.yield(.scanRequired)
              offset += MemoryLayout<inotify_event>.size + nameLength
              continue
            }

            var name: String?
            if nameLength > 0 {
              let namePtr = buffer.advanced(by: offset + MemoryLayout<inotify_event>.size)
              name = String(cString: namePtr.assumingMemoryBound(to: CChar.self))
            }

            if let name, !name.isEmpty, let watcher {
              let dirPath: String? = {
                _lock.lock()
                defer { _lock.unlock() }
                return _watchDescriptors[event.wd]
              }()

              if let dirPath {
                let fullPath = dirPath + "/" + name
                let relativePath = watcher.relativePath(for: fullPath)

                if !FileWatcher.shouldSkipPath(relativePath) {
                  let isDir = event.mask & UInt32(IN_ISDIR) != 0

                  if isDir {
                    if event.mask & UInt32(IN_CREATE) != 0 ||
                      event.mask & UInt32(IN_MOVED_TO) != 0
                    {
                      addWatchesRecursively(at: fullPath)
                    }
                  } else {
                    if event.mask & UInt32(IN_CREATE) != 0 ||
                      event.mask & UInt32(IN_MOVED_TO) != 0
                    {
                      continuation.yield(.created(path: relativePath))
                    } else if event.mask & UInt32(IN_MODIFY) != 0 ||
                      event.mask & UInt32(IN_ATTRIB) != 0
                    {
                      continuation.yield(.modified(path: relativePath))
                    } else if event.mask & UInt32(IN_DELETE) != 0 ||
                      event.mask & UInt32(IN_MOVED_FROM) != 0
                    {
                      continuation.yield(.deleted(path: relativePath))
                    }
                  }
                }
              }
            }

            offset += MemoryLayout<inotify_event>.size + nameLength
          }
        }
      }
    }

    func stop() {
      _lock.lock()
      _running = false
      _lock.unlock()

      // Signal the poll loop to stop.
      var byte: UInt8 = 1
      withUnsafePointer(to: &byte) { ptr in
        _ = Glibc.write(stopPipeWrite, ptr, 1)
      }

      // Remove all watches.
      _lock.lock()
      let descriptors = _watchDescriptors
      _lock.unlock()

      for wd in descriptors.keys {
        inotify_rm_watch(fd, wd)
      }

      close(fd)
      close(stopPipeRead)
      close(stopPipeWrite)
    }
  }

  extension FileWatcher {
    func startInotify(continuation: AsyncStream<FileWatchEvent>.Continuation) {
      let fd = inotify_init1(Int32(IN_NONBLOCK | IN_CLOEXEC))
      guard fd >= 0 else {
        continuation.finish()
        return
      }

      let context = InotifyContext(
        watcher: self,
        continuation: continuation,
        fd: fd,
      )

      context.addWatchesRecursively(at: root.path)

      _inotifyCtx.withLock { $0 = context }

      let thread = Thread {
        context.pollLoop()
      }
      thread.qualityOfService = .utility
      thread.name = "com.wuhu.filewatcher.inotify"
      thread.start()
    }

    func stopInotify() {
      let context: InotifyContext? = _inotifyCtx.withLock { ctx in
        let old = ctx as? InotifyContext
        ctx = nil
        return old
      }
      context?.stop()
    }
  }

#endif
