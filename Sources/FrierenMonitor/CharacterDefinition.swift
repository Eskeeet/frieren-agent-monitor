import Foundation

enum CharacterAnimation: String, CaseIterable, Hashable {
    case idle, runLeft, runRight, hi
    case reactionOne, reactionTwo, reactionThree
    case needsPrompt, jump
}

struct SpriteCell: Codable, Hashable {
    let row: Int
    let column: Int
}

enum CharacterSpriteSheet {
    case bundled(resource: String)
    case localFile(URL)

    var cacheKey: String {
        switch self {
        case .bundled(let resource): return "bundle:\(resource)"
        case .localFile(let url): return "file:\(url.path)"
        }
    }

    var url: URL? {
        switch self {
        case .bundled(let resource):
            return Bundle.main.url(forResource: resource, withExtension: "png")
        case .localFile(let url):
            return url
        }
    }
}

struct CharacterDefinition: Identifiable {
    let id: String
    let displayName: String
    let spriteSheet: CharacterSpriteSheet
    let cellWidth: Int
    let cellHeight: Int
    let animations: [CharacterAnimation: [SpriteCell]]

    static let frieren = CharacterDefinition(
        id: "frieren",
        displayName: "Frieren",
        spriteSheet: .bundled(resource: "frieren-spritesheet"),
        cellWidth: 192,
        cellHeight: 208,
        animations: legacyV1Animations
    )

    /// Add new bundled characters here after defining their sprite layout.
    static let bundled: [CharacterDefinition] = [.frieren]

    static let legacyV1Animations: [CharacterAnimation: [SpriteCell]] = [
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

    private static func cells(row: Int, columns: ClosedRange<Int>) -> [SpriteCell] {
        columns.map { SpriteCell(row: row, column: $0) }
    }

    static func loadLocalCharacters(fileManager: FileManager = .default) -> [CharacterDefinition] {
        let root = localCharactersDirectory(fileManager: fileManager)
        guard let directories = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return directories.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { directory in
            loadLocalCharacter(from: directory, fileManager: fileManager)
        }
    }

    static func localCharactersDirectory(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return applicationSupport
            .appendingPathComponent("Frieren Monitor", isDirectory: true)
            .appendingPathComponent("Characters", isDirectory: true)
    }

    private static func loadLocalCharacter(
        from directory: URL,
        fileManager: FileManager
    ) -> CharacterDefinition? {
        let manifestURL = directory.appendingPathComponent("character.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(LocalCharacterManifest.self, from: data),
              !manifest.id.isEmpty,
              !manifest.displayName.isEmpty,
              manifest.cellWidth > 0,
              manifest.cellHeight > 0 else { return nil }

        let sheetURL = directory.appendingPathComponent(manifest.spritesheet).standardizedFileURL
        let rootPath = directory.standardizedFileURL.path + "/"
        guard sheetURL.path.hasPrefix(rootPath),
              fileManager.fileExists(atPath: sheetURL.path),
              let animations = manifest.resolvedAnimations else { return nil }

        return CharacterDefinition(
            id: manifest.id,
            displayName: manifest.displayName,
            spriteSheet: .localFile(sheetURL),
            cellWidth: manifest.cellWidth,
            cellHeight: manifest.cellHeight,
            animations: animations
        )
    }
}

private struct LocalCharacterManifest: Decodable {
    let id: String
    let displayName: String
    let spritesheet: String
    let cellWidth: Int
    let cellHeight: Int
    let layout: String?
    let animations: [String: [SpriteCell]]?

    var resolvedAnimations: [CharacterAnimation: [SpriteCell]]? {
        let result: [CharacterAnimation: [SpriteCell]]
        if let animations {
            result = Dictionary(uniqueKeysWithValues: animations.compactMap { key, cells in
                guard let animation = CharacterAnimation(rawValue: key), !cells.isEmpty else { return nil }
                return (animation, cells)
            })
        } else {
            switch layout {
            case "legacy-v1":
                result = CharacterDefinition.legacyV1Animations
            case "static":
                let cell = [SpriteCell(row: 0, column: 0)]
                result = Dictionary(uniqueKeysWithValues: CharacterAnimation.allCases.map { ($0, cell) })
            default:
                return nil
            }
        }
        guard CharacterAnimation.allCases.allSatisfy({ animation in
            guard let cells = result[animation], !cells.isEmpty else { return false }
            return cells.allSatisfy { $0.row >= 0 && $0.column >= 0 }
        }) else { return nil }
        return result
    }
}

final class CharacterStore: ObservableObject {
    @Published private(set) var selected: CharacterDefinition
    let characters: [CharacterDefinition]

    private let defaults: UserDefaults
    private let selectionKey = "selectedCharacterID"

    init(
        characters: [CharacterDefinition]? = nil,
        defaults: UserDefaults = .standard
    ) {
        let candidates = characters
            ?? (CharacterDefinition.bundled + CharacterDefinition.loadLocalCharacters())
        var seenIDs = Set<String>()
        let available = candidates.filter { seenIDs.insert($0.id).inserted }
        precondition(!available.isEmpty, "At least one character must be available")
        self.characters = available
        self.defaults = defaults
        let savedID = defaults.string(forKey: selectionKey)
        self.selected = available.first(where: { $0.id == savedID }) ?? available[0]
    }

    func select(_ character: CharacterDefinition) {
        guard characters.contains(where: { $0.id == character.id }) else { return }
        selected = character
        defaults.set(character.id, forKey: selectionKey)
    }
}
