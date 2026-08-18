import AppKit
import SwiftUI

private enum SpriteAnimation {
    case idle, runLeft, runRight, wave
    case reactionOne, reactionTwo, reactionThree
    case needsPrompt, celebrating
}

struct FrierenSprite: View {
    let mood: PetMood
    let hovered: Bool
    let travelDirection: PetTravelDirection?
    let runningSessionCount: Int
    let reactingToClick: Bool
    let clickVariant: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: interval)) { timeline in
            let animation = animation(at: timeline.date)
            let frames = SpriteAtlas.frames(for: animation)
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
        .animation(.spring(response: 0.25, dampingFraction: 0.68), value: hovered)
        .accessibilityLabel(accessibilityLabel)
    }

    private var interval: TimeInterval {
        if travelDirection != nil { return 0.075 }
        if reactingToClick { return 0.14 }
        if hovered { return 0.2 }
        if mood == .needsInput { return 0.32 }
        if mood == .celebrating { return 0.22 }
        if runningSessionCount > 3 { return 0.09 }
        return 0.72
    }

    private func animation(at date: Date) -> SpriteAnimation {
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
        if hovered { return .wave }
        if mood == .needsInput { return .needsPrompt }
        if mood == .celebrating { return .celebrating }
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
        if let travelDirection {
            return "Frieren: running \(travelDirection == .left ? "left" : "right")"
        }
        if reactingToClick { return "Frieren: reacting" }
        if hovered { return "Frieren: waving" }
        if runningSessionCount > 3 { return "Frieren: running with busy sessions" }
        switch mood {
        case .sleeping: return "Frieren: no active sessions"
        case .watching: return "Frieren: watching sessions"
        case .working: return "Frieren: sessions running"
        case .needsInput: return "Frieren: a session needs input"
        case .celebrating: return "Frieren: a session finished"
        }
    }
}

private enum SpriteAtlas {
    private struct Cell: Hashable { let row: Int; let column: Int }
    private static let cellWidth = 192
    private static let cellHeight = 208
    private static let animationCells: [SpriteAnimation: [Cell]] = [
        .idle: (0...5).map { Cell(row: 0, column: $0) },
        .runLeft: (0...7).map { Cell(row: 2, column: $0) },
        .runRight: (0...7).map { Cell(row: 1, column: $0) },
        .wave: (0...3).map { Cell(row: 3, column: $0) },
        .reactionOne: (0...5).map { Cell(row: 7, column: $0) },
        .reactionTwo: (0...5).map { Cell(row: 8, column: $0) },
        .reactionThree: (0...4).map { Cell(row: 4, column: $0) },
        .needsPrompt: [Cell(row: 8, column: 4), Cell(row: 8, column: 5)],
        .celebrating: (0...3).map { Cell(row: 3, column: $0) },
    ]

    private static let cache: [Cell: NSImage] = {
        guard let url = Bundle.main.url(forResource: "frieren-spritesheet", withExtension: "png"),
              let source = NSImage(contentsOf: url),
              let image = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [:] }
        var result: [Cell: NSImage] = [:]
        for cell in Set(animationCells.values.flatMap { $0 }) {
            let rect = CGRect(x: cell.column * cellWidth, y: cell.row * cellHeight,
                              width: cellWidth, height: cellHeight)
            guard let crop = image.cropping(to: rect) else { continue }
            result[cell] = NSImage(cgImage: crop, size: NSSize(width: cellWidth, height: cellHeight))
        }
        return result
    }()

    static func frames(for animation: SpriteAnimation) -> [NSImage] {
        return (animationCells[animation] ?? []).compactMap { cache[$0] }
    }
}
