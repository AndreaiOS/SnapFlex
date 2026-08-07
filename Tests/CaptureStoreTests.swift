import Testing
import Foundation
@testable import SnapFlex

final class FakePhotoLibrary: PhotoLibraryProtocol {
    var isAuthorized = true
    var saved: [[CaptureResource]] = []
    var failNextSave = false

    func requestAuthorization() async -> Bool { isAuthorized }
    func save(_ resources: [CaptureResource]) async throws {
        if !isAuthorized || failNextSave {
            failNextSave = false
            throw NSError(domain: "test", code: 1)
        }
        saved.append(resources)
    }
}

@Suite struct CaptureStoreTests {
    func makeStore(authorized: Bool) -> (CaptureStore, FakePhotoLibrary, URL) {
        let library = FakePhotoLibrary()
        library.isAuthorized = authorized
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spool-\(UUID().uuidString)")
        return (CaptureStore(library: library, spoolDirectory: dir), library, dir)
    }

    let sample = [CaptureResource(kind: .rawDNG, data: Data([1, 2])),
                  CaptureResource(kind: .processedHEIF, data: Data([3]))]

    @Test func authorizedSavesDirectly() async {
        let (store, library, _) = makeStore(authorized: true)
        await store.store(sample)
        #expect(library.saved == [sample])
        #expect(store.spooledCount == 0)
    }

    @Test func unauthorizedSpoolsToDisk() async {
        let (store, library, _) = makeStore(authorized: false)
        await store.store(sample)
        #expect(library.saved.isEmpty)
        #expect(store.spooledCount == 1)
    }

    @Test func flushMovesSpoolToLibrary() async {
        let (store, library, _) = makeStore(authorized: false)
        await store.store(sample)
        library.isAuthorized = true
        await store.flushSpool()
        #expect(store.spooledCount == 0)
        #expect(library.saved.count == 1)
        #expect(library.saved[0].map(\.kind).sorted(by: { "\($0)" < "\($1)" })
                == sample.map(\.kind).sorted(by: { "\($0)" < "\($1)" }))
    }

    @Test func failedFlushKeepsSpool() async {
        let (store, library, _) = makeStore(authorized: false)
        await store.store(sample)
        library.isAuthorized = true
        library.failNextSave = true
        await store.flushSpool()
        #expect(store.spooledCount == 1)
    }

    @Test func partialGroupsAreIgnored() async {
        let (store, library, dir) = makeStore(authorized: true)
        let fm = FileManager.default
        let partialDir = dir.appendingPathComponent(UUID().uuidString + ".partial")
        try? fm.createDirectory(at: partialDir, withIntermediateDirectories: true)
        try? Data([1, 2]).write(to: partialDir.appendingPathComponent("raw.dng"))

        #expect(store.spooledCount == 0)
        library.isAuthorized = true
        await store.flushSpool()
        #expect(library.saved.isEmpty)
        #expect((try? fm.contentsOfDirectory(at: partialDir, includingPropertiesForKeys: nil)) != nil)
    }

    @Test func spooledGroupIsComplete() async {
        let (store, library, dir) = makeStore(authorized: false)
        await store.store(sample)

        let fm = FileManager.default
        guard let groups = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil),
              let groupDir = groups.first else {
            #expect(Bool(false), "No spool directory created")
            return
        }

        let rawExists = fm.fileExists(atPath: groupDir.appendingPathComponent("raw.dng").path)
        let heifExists = fm.fileExists(atPath: groupDir.appendingPathComponent("processed.heic").path)
        #expect(rawExists && heifExists)
    }
}
