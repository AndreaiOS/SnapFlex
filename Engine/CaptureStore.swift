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
        do {
            guard library.isAuthorized else { throw CocoaError(.fileWriteNoPermission) }
            try await library.save(resources)
        } catch {
            spool(resources)
        }
    }

    private func spool(_ resources: [CaptureResource]) {
        let uuid = UUID().uuidString
        let stagingDir = spoolDirectory.appendingPathComponent("\(uuid).partial")
        let finalDir = spoolDirectory.appendingPathComponent(uuid)

        do {
            try fileManager.createDirectory(at: stagingDir, withIntermediateDirectories: true)

            // Write all files to staging directory with atomic writes
            for resource in resources {
                let name = resource.kind == .rawDNG ? "raw.dng" : "processed.heic"
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
            var resources: [CaptureResource] = []
            let rawURL = group.appendingPathComponent("raw.dng")
            let heifURL = group.appendingPathComponent("processed.heic")
            if let data = try? Data(contentsOf: rawURL) {
                resources.append(CaptureResource(kind: .rawDNG, data: data))
            }
            if let data = try? Data(contentsOf: heifURL) {
                resources.append(CaptureResource(kind: .processedHEIF, data: data))
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
}
