import Foundation
import SwiftUI

enum Harness: String, CaseIterable, Codable {
    case claude, codex, cursor

    var label: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        }
    }

    var color: Color {
        switch self {
        case .claude: return Color(red: 0.87, green: 0.48, blue: 0.31)
        case .codex: return Color(red: 0.20, green: 0.78, blue: 0.52)
        case .cursor: return Color(red: 0.52, green: 0.57, blue: 0.98)
        }
    }
}

enum MonitorState: String, Codable {
    case running, waiting, finished

    var label: String {
        switch self {
        case .running: return "Running"
        case .waiting: return "Needs input"
        case .finished: return "Finished"
        }
    }
}

struct AgentSession: Identifiable, Equatable {
    let id: Int
    let pid: Int
    let harness: Harness
    let projectPath: String?
    let title: String?
    let startedAt: Date
    var updatedAt: Date
    var state: MonitorState

    var displayName: String {
        if let title, !title.isEmpty, title != "main-agent" { return title }
        if let projectPath, projectPath != "/" {
            let name = URL(fileURLWithPath: projectPath).lastPathComponent
            if !name.isEmpty { return name }
        }
        return harness.label
    }
}

enum PetMood: Hashable {
    case sleeping, watching, working, needsInput, celebrating
}
