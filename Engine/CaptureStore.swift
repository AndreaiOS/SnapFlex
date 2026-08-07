import Foundation
import Photos
import UniformTypeIdentifiers

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

    init(library: PhotoLibraryProtocol, spoolDirectory: URL) {
        self.library = library
        self.spoolDirectory = spoolDirectory
        try? fileManager.createDirectory(at: spoolDirectory, withIntermediateDirectories: true)
    }

    var spooledCount: Int {
        (try? fileManager.contentsOfDirectory(at: spoolDirectory,
                                              includingPropertiesForKeys: nil))?.count ?? 0
    }

    func store(_ resources: [CaptureResource]) async {
        guard !resources.isEmpty else { return }
        do {
            guard library.isAuthorized else { throw CocoaError(.fileWriteNoPermission) }
            try await library.save(resources)
        } catch {
            spool(resources)
        }
    }

    private func spool(_ resources: [CaptureResource]) {
        let dir = spoolDirectory.appendingPathComponent(UUID().uuidString)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        for resource in resources {
            let name = resource.kind == .rawDNG ? "raw.dng" : "processed.heic"
            try? resource.data.write(to: dir.appendingPathComponent(name))
        }
    }

    func flushSpool() async {
        guard library.isAuthorized,
              let groups = try? fileManager.contentsOfDirectory(
                  at: spoolDirectory, includingPropertiesForKeys: nil) else { return }
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
