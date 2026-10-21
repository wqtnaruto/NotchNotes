import AppKit
import Foundation
import MarkdownEngine

final class LocalImageStore: EmbeddedImageFileProvider, @unchecked Sendable {
    static let contentDidChangeNotification = Notification.Name("NotchNotes.LocalImageStore.contentDidChange")

    private struct ImageAssetRecord: Codable, Sendable {
        var id: String
        var displayName: String
        var storedFilename: String
        var originalPath: String?
        var sourceKind: String
        var createdAt: Date
    }

    private let directoryURL: URL
    private let manifestURL: URL
    private let lock = NSLock()
    private let ioQueue = DispatchQueue(label: "io.github.oiloil.NotchNotes.images", qos: .utility)
    private let dataWriter: @Sendable (Data, URL) throws -> Void
    private var records: [String: ImageAssetRecord]
    private var cachedImages: [String: NSImage] = [:]
    private var loadingImageIDs: Set<String> = []
    private var version = 0
    private let imageExtension = "png"

    convenience init() {
        let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.init(directoryURL: supportURL.appendingPathComponent("NotchNotes/Images", isDirectory: true))
    }

    init(
        directoryURL: URL,
        dataWriter: @escaping @Sendable (Data, URL) throws -> Void = LocalImageStore.writeData
    ) {
        self.directoryURL = directoryURL
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        manifestURL = directoryURL.appendingPathComponent("manifest.json")
        self.dataWriter = dataWriter
        records = Self.loadRecords(from: manifestURL)
    }

    func saveImage(from pasteboard: NSPasteboard) -> String? {
        if let fileURL = PasteboardImageReader.imageFileURL(from: pasteboard),
           fileURL.isFileURL {
            return enqueueSave(
                originalName: fileURL.deletingPathExtension().lastPathComponent,
                originalFileURL: fileURL,
                sourceKind: "file"
            ) {
                guard let data = try? Data(contentsOf: fileURL), NSImage(data: data) != nil else { return nil }
                return self.pngData(fromImageData: data) ?? data
            }
        }

        if let pngData = pasteboard.data(forType: .png), !pngData.isEmpty {
            return enqueueSave(
                originalName: "pasted-image",
                originalFileURL: nil,
                sourceKind: "clipboardImage"
            ) {
                pngData
            }
        }

        guard let imageData = PasteboardImageReader.imageData(from: pasteboard) else {
            return nil
        }

        return enqueueSave(
            originalName: "pasted-image",
            originalFileURL: nil,
            sourceKind: "clipboardImage"
        ) { imageData }
    }

    func image(for reference: EmbeddedImageRequest) -> NSImage? {
        let candidateNames = [reference.id, reference.name].compactMap { $0 }

        for candidateName in candidateNames {
            if let image = cachedImage(for: candidateName) { return image }
            scheduleImageLoadIfNeeded(for: candidateName)
        }

        return nil
    }

    func storedFileURL(for reference: EmbeddedImageRequest) -> URL? {
        guard let candidateName = recordCandidateNames(for: reference).first(where: { !$0.isEmpty }) else {
            return nil
        }

        lock.lock()
        let record = records[candidateName]
        lock.unlock()

        if let record {
            let url = directoryURL.appendingPathComponent(record.storedFilename)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }

        let fallbackURL = imageURL(for: candidateName)
        return FileManager.default.fileExists(atPath: fallbackURL.path) ? fallbackURL : nil
    }

    func originalFileURL(for reference: EmbeddedImageRequest) -> URL? {
        guard let candidateName = recordCandidateNames(for: reference).first(where: { !$0.isEmpty }) else {
            return nil
        }

        lock.lock()
        let path = records[candidateName]?.originalPath
        lock.unlock()

        guard let path else { return nil }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func fingerprint() -> AnyHashable {
        lock.lock()
        defer { lock.unlock() }
        return version
    }

    func flush() {
        ioQueue.sync {}
    }

    private func enqueueSave(
        originalName: String,
        originalFileURL: URL?,
        sourceKind: String,
        loadData: @escaping @Sendable () -> Data?
    ) -> String {
        let displayName = sanitizedDisplayName(originalName)
        let id = UUID()
        let storedFilename = "\(id.uuidString).\(imageExtension)"
        let url = imageURL(for: id.uuidString)
        let record = ImageAssetRecord(
            id: id.uuidString,
            displayName: displayName,
            storedFilename: storedFilename,
            originalPath: originalFileURL?.path,
            sourceKind: sourceKind,
            createdAt: Date()
        )
        lock.withLock { records[id.uuidString] = record }
        let writer = dataWriter
        ioQueue.async { [weak self] in
            guard let self else { return }
            guard let data = loadData() else {
                self.lock.withLock { self.records[id.uuidString] = nil }
                return
            }
            do {
                try writer(data, url)
                let image = NSImage(data: data)
                let recordsToSave = self.lock.withLock { () -> [String: ImageAssetRecord] in
                    if let image { self.cachedImages[id.uuidString] = image }
                    self.version += 1
                    return self.records
                }
                self.saveRecords(recordsToSave)
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Self.contentDidChangeNotification, object: self)
                }
            } catch {
                self.lock.withLock { self.records[id.uuidString] = nil }
            }
        }
        return "![[\(displayName)|\(id.uuidString)]]"
    }

    private func cachedImage(for id: String) -> NSImage? {
        lock.withLock { cachedImages[id] }
    }

    private func scheduleImageLoadIfNeeded(for candidateName: String) {
        let load: (String, URL)? = lock.withLock {
            let id = records[candidateName]?.id ?? candidateName
            guard cachedImages[id] == nil, loadingImageIDs.insert(id).inserted else { return nil }
            let filename = records[candidateName]?.storedFilename ?? "\(candidateName).\(imageExtension)"
            return (id, directoryURL.appendingPathComponent(filename))
        }
        guard let (id, url) = load else { return }
        ioQueue.async { [weak self] in
            guard let self else { return }
            let image = NSImage(contentsOf: url)
            self.lock.withLock {
                self.loadingImageIDs.remove(id)
                if let image {
                    self.cachedImages[id] = image
                    self.version += 1
                }
            }
            guard image != nil else { return }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.contentDidChangeNotification, object: self)
            }
        }
    }

    private func recordCandidateNames(for reference: EmbeddedImageRequest) -> [String] {
        [reference.id, reference.name].compactMap { $0 }
    }

    private func imageURL(for idOrName: String) -> URL {
        if idOrName.lowercased().hasSuffix(".\(imageExtension)") {
            return directoryURL.appendingPathComponent(idOrName)
        }

        return directoryURL.appendingPathComponent("\(idOrName).\(imageExtension)")
    }

    private func sanitizedDisplayName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? "pasted-image" : trimmed
        return fallback
            .replacingOccurrences(of: "|", with: "-")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private func pngData(fromImageData data: Data) -> Data? {
        guard let image = NSImage(data: data),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }

    private static func loadRecords(from url: URL) -> [String: ImageAssetRecord] {
        guard let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([ImageAssetRecord].self, from: data) else {
            return [:]
        }

        return Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
    }

    private func saveRecords(_ records: [String: ImageAssetRecord]) {
        let sortedRecords = records.values.sorted { $0.createdAt < $1.createdAt }
        guard let data = try? JSONEncoder().encode(sortedRecords) else { return }
        try? dataWriter(data, manifestURL)
    }

    nonisolated private static func writeData(_ data: Data, _ url: URL) throws {
        try data.write(to: url, options: .atomic)
    }
}
