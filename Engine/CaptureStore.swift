import Foundation
import Photos
import UniformTypeIdentifiers
import os

protocol PhotoLibraryProtocol {
    var isAuthorized: Bool { get }
    func requestAuthorization() async -> Bool
    func save(_ resources: [CaptureResource]) async throws
}

final class PhotoKitLibrary: PhotoLibraryProtocol {
    var isAuthorized: Bool {
        PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized
    }

    func requestAuthorization() async -> Bool {
        await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized
    }

    func save(_ resources: [CaptureResource]) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let heif = resources.first { $0.kind == .processedHEIF }
            let raws = resources.filter { $0.kind == .rawDNG }
            if let heif {
                request.addResource(with: .photo, data: heif.data, options: nil)
                for raw in raws {
                    let options = PHAssetResourceCreationOptions()
                    options.uniformTypeIdentifier = UTType.dng.identifier
                    request.addResource(with: .alternatePhoto, data: raw.data, options: options)
                }
            } else if let first = raws.first {
                let options = PHAssetResourceCreationOptions()
                options.uniformTypeIdentifier = UTType.dng.identifier
                request.addResource(with: .photo, data: first.data, options: options)
                for raw in raws.dropFirst() {
                    let extra = PHAssetResourceCreationOptions()
                    extra.uniformTypeIdentifier = UTType.dng.identifier
                    request.addResource(with: .alternatePhoto, data: raw.data, options: extra)
                }
            }
        }
    }
}

final class CaptureStore {
    private let library: PhotoLibraryProtocol
    private let spoolDirectory: URL
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "co.socialsprint.snapflex", category: "capture-store")

    init(library: PhotoLibraryProtocol, spoolDirectory: URL) {
        self.library = library
        self.spoolDirectory = spoolDirectory
        try? fileManager.createDirectory(at: spoolDirectory, withIntermediateDirectories: true)
    }

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
