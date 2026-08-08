import Foundation
import Photos
import os

protocol PhotoLibraryProtocol {
    var isAuthorized: Bool { get }
    var isDenied: Bool { get }
    func requestAuthorization() async -> Bool
    func save(_ resources: [CaptureResource]) async throws
}

extension PhotoLibraryProtocol {
    var isDenied: Bool { false }
}

final class PhotoKitLibrary: PhotoLibraryProtocol {
    var isAuthorized: Bool {
        PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized
    }

    var isDenied: Bool {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .denied, .restricted: true
        default: false
        }
    }

    func requestAuthorization() async -> Bool {
        await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized
    }

    func save(_ resources: [CaptureResource]) async throws {
        let heif = resources.first { $0.kind == .processedHEIF }
        let raws = resources.filter { $0.kind == .rawDNG }

        // Photos rejects data-based DNG resources with PHPhotosErrorDomain 3300
        // (changeNotSupported): its writer needs a filename to identify the RAW
        // format. Stage each DNG as a temporary .dng file and add it by fileURL.
        var rawURLs: [URL] = []
        for (index, raw) in raws.enumerated() {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("snapflex-save-\(UUID().uuidString)-\(index).dng")
            try raw.data.write(to: url)
            rawURLs.append(url)
        }
        defer {
            for url in rawURLs { try? FileManager.default.removeItem(at: url) }
        }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            if let heif {
                request.addResource(with: .photo, data: heif.data, options: nil)
                for url in rawURLs {
                    request.addResource(with: .alternatePhoto, fileURL: url, options: nil)
                }
            } else if let first = rawURLs.first {
                request.addResource(with: .photo, fileURL: first, options: nil)
                for url in rawURLs.dropFirst() {
                    request.addResource(with: .alternatePhoto, fileURL: url, options: nil)
                }
            }
        }
    }
}

final class CaptureStore {
    private let library: PhotoLibraryProtocol
    private let spoolDirectory: URL
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "co.SnapFlex", category: "capture-store")
    private let flushGuard = NSLock()
    private var isFlushing = false

    init(library: PhotoLibraryProtocol, spoolDirectory: URL) {
        self.library = library
        self.spoolDirectory = spoolDirectory
        try? fileManager.createDirectory(at: spoolDirectory, withIntermediateDirectories: true)
    }

    /// True when Photos access is explicitly denied or restricted — saves can only spool.
    var saveBlocked: Bool { library.isDenied }

    var spooledCount: Int {
        let contents = (try? fileManager.contentsOfDirectory(at: spoolDirectory,
                                                              includingPropertiesForKeys: nil)) ?? []
        return contents.filter { !$0.lastPathComponent.hasSuffix(".partial") }.count
    }

    func store(_ resources: [CaptureResource]) async {
        guard !resources.isEmpty else { return }
        if !library.isAuthorized {
            let granted = await library.requestAuthorization()
            if granted {
                await flushSpool()
            }
        }
        let groups = Dictionary(grouping: resources, by: \.frameIndex)
            .sorted { $0.key < $1.key }
        for (_, group) in groups {
            do {
                guard library.isAuthorized else { throw CocoaError(.fileWriteNoPermission) }
                try await library.save(group)
            } catch {
                logger.error("Photo library save failed, spooling: \(String(describing: error))")
                spool(group)
            }
        }
    }

    private func spool(_ resources: [CaptureResource]) {
        let uuid = UUID().uuidString
        let stagingDir = spoolDirectory.appendingPathComponent("\(uuid).partial")
        let finalDir = spoolDirectory.appendingPathComponent(uuid)

        do {
            try fileManager.createDirectory(at: stagingDir, withIntermediateDirectories: true)

            // Write all files to staging directory with atomic writes; filenames are
            // unique per frame so bracket frames spooled into the same group never collide.
            for resource in resources {
                let name = resource.kind == .rawDNG
                    ? "raw-\(resource.frameIndex).dng"
                    : "processed-\(resource.frameIndex).heic"
                let fileURL = stagingDir.appendingPathComponent(name)
                try resource.data.write(to: fileURL, options: .atomic)
            }

            // All writes succeeded; move to final directory
            try fileManager.moveItem(at: stagingDir, to: finalDir)
        } catch {
            // Clean up staging directory; never leave a partial
            try? fileManager.removeItem(at: stagingDir)
            logger.error("Failed to spool capture: \(error.localizedDescription)")
        }
    }

    func flushSpool() async {
        // Non-reentrant: launch .task, scenePhase and post-grant store() can all
        // trigger a flush concurrently; two flushes of the same group would save
        // duplicate assets.
        flushGuard.lock()
        if isFlushing { flushGuard.unlock(); return }
        isFlushing = true
        flushGuard.unlock()
        defer { flushGuard.lock(); isFlushing = false; flushGuard.unlock() }
        guard library.isAuthorized,
              let allGroups = try? fileManager.contentsOfDirectory(
                  at: spoolDirectory, includingPropertiesForKeys: nil) else { return }
        let groups = allGroups.filter { !$0.lastPathComponent.hasSuffix(".partial") }
        for group in groups {
            guard let files = try? fileManager.contentsOfDirectory(
                      at: group, includingPropertiesForKeys: nil) else { continue }
            var resources: [CaptureResource] = []
            for file in files {
                let name = file.lastPathComponent
                guard let data = try? Data(contentsOf: file) else { continue }
                if name.hasPrefix("raw-"), name.hasSuffix(".dng") {
                    let frameIndex = Self.parseFrameIndex(from: name, prefix: "raw-", suffix: ".dng")
                    resources.append(CaptureResource(kind: .rawDNG, data: data, frameIndex: frameIndex))
                } else if name.hasPrefix("processed-"), name.hasSuffix(".heic") {
                    let frameIndex = Self.parseFrameIndex(from: name, prefix: "processed-", suffix: ".heic")
                    resources.append(CaptureResource(kind: .processedHEIF, data: data, frameIndex: frameIndex))
                }
            }
            guard !resources.isEmpty else { try? fileManager.removeItem(at: group); continue }
            do {
                try await library.save(resources)
                try? fileManager.removeItem(at: group)
            } catch {
                // keep spooled; retry on next flush
            }
        }
    }

    private static func parseFrameIndex(from name: String, prefix: String, suffix: String) -> Int {
        guard name.count >= prefix.count + suffix.count else { return 0 }
        let start = name.index(name.startIndex, offsetBy: prefix.count)
        let end = name.index(name.endIndex, offsetBy: -suffix.count)
        guard start <= end, let value = Int(name[start..<end]) else { return 0 }
        return value
    }
}
