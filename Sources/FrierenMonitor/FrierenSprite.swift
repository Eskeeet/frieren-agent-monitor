import AppKit
import SwiftUI

struct FrierenSprite: View {
    let mood: PetMood
    let hovered: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: interval)) { timeline in
            let frames = SpriteAtlas.frames(for: mood)
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
        switch mood {
        case .working: return 0.12
        case .needsInput: return 0.4
        case .celebrating: return 0.32
        case .watching: return 0.72
        case .sleeping: return 0.85
        }
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
    private static let cells: [PetMood: [Cell]] = [
        .sleeping: (1...6).map { Cell(row: 5, column: $0) },
        .watching: (0...5).map { Cell(row: 0, column: $0) },
        .working: (0...7).map { Cell(row: 1, column: $0) },
        .needsInput: [Cell(row: 8, column: 4), Cell(row: 8, column: 5)],
        .celebrating: (0...3).map { Cell(row: 3, column: $0) },
    ]

    private static let cache: [Cell: NSImage] = {
        guard let url = Bundle.main.url(forResource: "frieren-spritesheet", withExtension: "png"),
              let source = NSImage(contentsOf: url),
              let image = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [:] }
        var result: [Cell: NSImage] = [:]
        for cell in Set(cells.values.flatMap { $0 }) {
            let rect = CGRect(x: cell.column * cellWidth, y: cell.row * cellHeight,
                              width: cellWidth, height: cellHeight)
            guard let crop = image.cropping(to: rect) else { continue }
            result[cell] = NSImage(cgImage: crop, size: NSSize(width: cellWidth, height: cellHeight))
        }
        return result
    }()

    static func frames(for mood: PetMood) -> [NSImage] {
        (cells[mood] ?? []).compactMap { cache[$0] }
    }
}
