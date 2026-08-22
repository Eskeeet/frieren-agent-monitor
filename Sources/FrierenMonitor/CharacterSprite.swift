import AppKit
import SwiftUI

struct CharacterSprite: View {
    let character: CharacterDefinition
    let mood: PetMood
    let hovered: Bool
    let travelDirection: PetTravelDirection?
    let runningSessionCount: Int
    let reactingToClick: Bool
    let clickVariant: Int
    let sayingHi: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: interval)) { timeline in
            let animation = animation(at: timeline.date)
            let frames = CharacterSpriteAtlas.frames(for: animation, character: character)
            let index = Int(timeline.date.timeIntervalSinceReferenceDate / interval) % max(frames.count, 1)
            Group {
                if frames.indices.contains(index) {
                    Image(nsImage: frames[index])
                        .resizable()
                        .interpolation(.none)
                        .antialiased(false)
                        .scaledToFit()
                } else {
                    Image(systemName: "wand.and.stars")
                        .resizable().scaledToFit().padding(28)
                }
            }
            .scaleEffect(hovered ? 1.04 : 1)
            .shadow(color: haloColor.opacity(0.55), radius: haloRadius)
        }
        .id(character.id)
        .animation(.spring(response: 0.25, dampingFraction: 0.68), value: hovered)
        .accessibilityLabel(accessibilityLabel)
    }

    private var interval: TimeInterval {
        if travelDirection != nil { return 0.075 }
        if reactingToClick { return 0.14 }
        if sayingHi { return 0.2 }
        if hovered { return 0.2 }
        if mood == .needsInput { return 0.32 }
        if mood == .celebrating { return 0.22 }
        if runningSessionCount > 3 { return 0.09 }
        return 0.72
    }

    private func animation(at date: Date) -> CharacterAnimation {
        if let travelDirection {
            return travelDirection == .left ? .runLeft : .runRight
        }
        if reactingToClick {
            switch clickVariant % 3 {
            case 0: return .reactionOne
            case 1: return .reactionTwo
            default: return .reactionThree
            }
        }
        if hovered || sayingHi { return .hi }
        if mood == .needsInput { return .needsPrompt }
        if mood == .celebrating { return .jump }
        if runningSessionCount > 3 {
            let phase = Int(date.timeIntervalSinceReferenceDate / 1.6)
            return phase.isMultiple(of: 2) ? .runLeft : .runRight
        }
        return .idle
    }

    private var haloColor: Color {
        switch mood {
        case .needsInput: return .orange
        case .celebrating: return .green
        case .working: return .cyan
        default: return .clear
        }
    }

    private var haloRadius: CGFloat {
        switch mood {
        case .needsInput, .celebrating: return 14
        case .working: return 7
        default: return 0
        }
    }

    private var accessibilityLabel: String {
        let name = character.displayName
        if let travelDirection {
            return "\(name): running \(travelDirection == .left ? "left" : "right")"
        }
        if reactingToClick { return "\(name): reacting" }
        if hovered { return "\(name): waving" }
        if sayingHi { return "\(name): saying hi" }
        if runningSessionCount > 3 { return "\(name): running with busy sessions" }
        switch mood {
        case .sleeping: return "\(name): no active sessions"
        case .watching: return "\(name): watching sessions"
        case .working: return "\(name): sessions running"
        case .needsInput: return "\(name): a session needs input"
        case .celebrating: return "\(name): a session finished"
        }
    }
}

private enum CharacterSpriteAtlas {
    private static var caches: [String: [SpriteCell: NSImage]] = [:]
    private static let lock = NSLock()

    static func frames(
        for animation: CharacterAnimation,
        character: CharacterDefinition
    ) -> [NSImage] {
        let cache = cachedFrames(for: character)
        return (character.animations[animation] ?? []).compactMap { cache[$0] }
    }

    private static func cachedFrames(for character: CharacterDefinition) -> [SpriteCell: NSImage] {
        lock.lock()
        defer { lock.unlock() }
        if let cache = caches[character.id] { return cache }

        guard let url = Bundle.main.url(
            forResource: character.spriteSheetResource,
            withExtension: "png"
        ), let source = NSImage(contentsOf: url),
           let image = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            caches[character.id] = [:]
            return [:]
        }

        var result: [SpriteCell: NSImage] = [:]
        let cells = Set(character.animations.values.flatMap { $0 })
        for cell in cells {
            let rect = CGRect(
                x: cell.column * character.cellWidth,
                y: cell.row * character.cellHeight,
                width: character.cellWidth,
                height: character.cellHeight
            )
            guard let crop = image.cropping(to: rect) else { continue }
            result[cell] = NSImage(
                cgImage: crop,
                size: NSSize(width: character.cellWidth, height: character.cellHeight)
            )
        }
        caches[character.id] = result
        return result
    }
}
