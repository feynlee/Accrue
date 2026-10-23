import Foundation

/// Where AccrueData lives. The app uses `JSONFileStore`; tests use `MemoryStore`.
/// Swapping in SwiftData with CloudKit later only needs another conformance.
public protocol DataStore: Sendable {
    func load() throws -> AccrueData?
    func save(_ data: AccrueData) throws
}

/// One JSON file, replaced atomically on every save.
public struct JSONFileStore: DataStore {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `Application Support/Accrue/accrue.json`.
    public static func standard() throws -> JSONFileStore {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let folder = base.appendingPathComponent("Accrue", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return JSONFileStore(url: folder.appendingPathComponent("accrue.json"))
    }

    public func load() throws -> AccrueData? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONFileStore.decoder.decode(AccrueData.self, from: data)
    }

    public func save(_ data: AccrueData) throws {
        let bytes = try JSONFileStore.encoder.encode(data)
        try bytes.write(to: url, options: [.atomic])
    }

    static var encoder: JSONEncoder {
        // Dates keep their default encoding (seconds as a Double) so sets logged within
        // the same second keep their order.
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }

    static var decoder: JSONDecoder {
        JSONDecoder()
    }
}

/// Keeps data in memory, for tests and previews.
public final class MemoryStore: DataStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: AccrueData?

    public init(_ data: AccrueData? = nil) {
        stored = data
    }

    public func load() throws -> AccrueData? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    public func save(_ data: AccrueData) throws {
        lock.lock(); defer { lock.unlock() }
        stored = data
    }
}
