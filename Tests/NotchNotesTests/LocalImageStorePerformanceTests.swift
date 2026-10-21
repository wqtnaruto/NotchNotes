import AppKit
import MarkdownEngine
import XCTest
@testable import NotchNotes

final class LocalImageStorePerformanceTests: XCTestCase {
    func testPastedImageReturnsBeforeSlowDiskWriteCompletes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalImageStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = SlowImageWriter(delay: 0.20)
        let store = LocalImageStore(directoryURL: directory, dataWriter: writer.write)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("LocalImageStoreTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setData(makePNG(), forType: .png)

        let start = ContinuousClock.now
        let reference = store.saveImage(from: pasteboard)
        let elapsed = ContinuousClock.now - start

        XCTAssertNotNil(reference)
        XCTAssertLessThan(elapsed, .milliseconds(100))
        store.flush()
        XCTAssertGreaterThanOrEqual(writer.writeCount, 1)
    }

    func testAsyncSavePersistsImageAndManifestForReload() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalImageStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("LocalImageStoreTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setData(makePNG(), forType: .png)

        let store = LocalImageStore(directoryURL: directory)
        let markdown = try XCTUnwrap(store.saveImage(from: pasteboard))
        store.flush()
        let id = try XCTUnwrap(markdown.split(separator: "|").last.map { String($0.dropLast(2)) })
        let reference = EmbeddedImageRequest(name: "pasted-image", id: id)

        let reloadedStore = LocalImageStore(directoryURL: directory)
        XCTAssertNotNil(reloadedStore.storedFileURL(for: reference))
        XCTAssertNil(reloadedStore.image(for: reference))
        reloadedStore.flush()
        XCTAssertNotNil(reloadedStore.image(for: reference))
    }

    private func makePNG() -> Data {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 4,
            bitsPerPixel: 32
        )!
        return bitmap.representation(using: .png, properties: [:])!
    }
}

private final class SlowImageWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let delay: TimeInterval
    private var count = 0

    init(delay: TimeInterval) { self.delay = delay }
    var writeCount: Int { lock.withLock { count } }

    func write(_ data: Data, _ url: URL) throws {
        Thread.sleep(forTimeInterval: delay)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        lock.withLock { count += 1 }
    }
}
