import Foundation

public struct Recipe: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var iso: Float?
    public var shutterSeconds: Double?
    public var evBias: Float
    public var wbKelvin: Int?
    public var raw: RAWMode
    public var heifCompanion: Bool
    public var processing: ProcessingLevel
    public var aspectIndex: Int

    public init(
        id: UUID = UUID(),
        name: String,
        iso: Float?,
        shutterSeconds: Double?,
        evBias: Float,
        wbKelvin: Int?,
        raw: RAWMode,
        heifCompanion: Bool,
        processing: ProcessingLevel,
        aspectIndex: Int
    ) {
        self.id = id
        self.name = name
        self.iso = iso
        self.shutterSeconds = shutterSeconds
        self.evBias = evBias
        self.wbKelvin = wbKelvin
        self.raw = raw
        self.heifCompanion = heifCompanion
        self.processing = processing
        self.aspectIndex = aspectIndex
    }
}

public struct RecipeBook: Equatable, Sendable {
    public private(set) var recipes: [Recipe]

    public init() {
        self.recipes = []
    }

    public init(data: Data) {
        do {
            let decoder = JSONDecoder()
            self.recipes = try decoder.decode([Recipe].self, from: data)
        } catch {
            self.recipes = []
        }
    }

    public func encode() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        do {
            return try encoder.encode(recipes)
        } catch {
            return Data()
        }
    }

    public mutating func add(_ recipe: Recipe) {
        if let index = recipes.firstIndex(where: { $0.name == recipe.name }) {
            recipes[index] = recipe
        } else {
            recipes.append(recipe)
        }
    }

    public mutating func remove(id: UUID) {
        recipes.removeAll { $0.id == id }
    }
}
