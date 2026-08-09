import Testing
import Foundation
@testable import SnapFlexCore

@Suite struct RecipesTests {
    func sample(_ name: String) -> Recipe {
        Recipe(name: name, iso: 200, shutterSeconds: 1.0/120, evBias: 0.3,
               wbKelvin: 5600, raw: .bayer, heifCompanion: true,
               processing: .zero, aspectIndex: 0)
    }

    @Test func roundTripsThroughData() {
        var book = RecipeBook()
        book.add(sample("Street"))
        book.add(sample("Portrait"))
        let restored = RecipeBook(data: book.encode())
        #expect(restored == book)
    }

    @Test func addReplacesSameName() {
        var book = RecipeBook()
        book.add(sample("Street"))
        var updated = sample("Street"); updated.iso = 800
        book.add(updated)
        #expect(book.recipes.count == 1)
        #expect(book.recipes[0].iso == 800)
    }

    @Test func removeById() {
        var book = RecipeBook()
        let r = sample("Street")
        book.add(r); book.add(sample("Portrait"))
        book.remove(id: r.id)
        #expect(book.recipes.map(\.name) == ["Portrait"])
    }

    @Test func corruptDataYieldsEmptyBook() {
        #expect(RecipeBook(data: Data([0x00, 0x01])).recipes.isEmpty)
    }
}
