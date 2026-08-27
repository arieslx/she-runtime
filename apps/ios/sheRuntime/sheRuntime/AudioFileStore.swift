import AVFoundation
import Foundation

struct AudioFileInfo: Equatable {
    let url: URL
    let duration: TimeInterval
    let sizeInBytes: Int64
}

struct AudioFileStore {
    private let fileManager: FileManager
    private let directoryURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("AudioProbe", isDirectory: true)
    }

    func makeRecordingURL() throws -> URL {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let safeTimestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")

        return directoryURL
            .appendingPathComponent("audio-probe-\(safeTimestamp)-\(UUID().uuidString).m4a")
    }

    func inspect(_ url: URL) async throws -> AudioFileInfo {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let duration = try await AVURLAsset(url: url).load(.duration).seconds
        return AudioFileInfo(url: url, duration: duration, sizeInBytes: size)
    }

    func delete(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func exists(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func mostRecentRecordingURL() throws -> URL? {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return nil }

        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "m4a" }

        return try urls.max { first, second in
            let firstDate = try first.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            let secondDate = try second.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            return firstDate < secondDate
        }
    }
}
