import Foundation

enum CharacterAnimation: Hashable {
    case idle, runLeft, runRight, hi
    case reactionOne, reactionTwo, reactionThree
    case needsPrompt, jump
}

struct SpriteCell: Hashable {
    let row: Int
    let column: Int
}

struct CharacterDefinition: Identifiable {
    let id: String
    let displayName: String
    let spriteSheetResource: String
    let cellWidth: Int
    let cellHeight: Int
    let animations: [CharacterAnimation: [SpriteCell]]

    static let frieren = CharacterDefinition(
        id: "frieren",
        displayName: "Frieren",
        spriteSheetResource: "frieren-spritesheet",
        cellWidth: 192,
        cellHeight: 208,
        animations: [
            .idle: cells(row: 0, columns: 0...5),
            .runLeft: cells(row: 2, columns: 0...7),
            .runRight: cells(row: 1, columns: 0...7),
            .hi: cells(row: 3, columns: 0...3),
            .reactionOne: cells(row: 7, columns: 0...5),
            .reactionTwo: cells(row: 8, columns: 0...5),
            .reactionThree: cells(row: 4, columns: 0...4),
            .needsPrompt: [SpriteCell(row: 8, column: 4), SpriteCell(row: 8, column: 5)],
            .jump: cells(row: 4, columns: 0...4),
        ]
    )

    /// Add new bundled characters here after defining their sprite layout.
    static let bundled: [CharacterDefinition] = [.frieren]

    private static func cells(row: Int, columns: ClosedRange<Int>) -> [SpriteCell] {
        columns.map { SpriteCell(row: row, column: $0) }
    }
}

final class CharacterStore: ObservableObject {
    @Published private(set) var selected: CharacterDefinition
    let characters: [CharacterDefinition]

    private let defaults: UserDefaults
    private let selectionKey = "selectedCharacterID"

    init(
        characters: [CharacterDefinition] = CharacterDefinition.bundled,
        defaults: UserDefaults = .standard
    ) {
        precondition(!characters.isEmpty, "At least one character must be available")
        self.characters = characters
        self.defaults = defaults
        let savedID = defaults.string(forKey: selectionKey)
        self.selected = characters.first(where: { $0.id == savedID }) ?? characters[0]
    }

    func select(_ character: CharacterDefinition) {
        guard characters.contains(where: { $0.id == character.id }) else { return }
        selected = character
        defaults.set(character.id, forKey: selectionKey)
    }
}
