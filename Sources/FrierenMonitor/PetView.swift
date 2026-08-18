import AppKit
import SwiftUI

struct PetView: View {
    @ObservedObject var monitor: SessionMonitor
    let quit: () -> Void
    let setExpanded: (Bool) -> Void
    @State private var hoveringPet = false
    @State private var hoveringCard = false

    private var expanded: Bool { hoveringPet || hoveringCard }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear
            if expanded {
                sessionCard
                    .frame(width: 300, height: 218)
                    .padding(.trailing, 112)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .onHover { hoveringCard = $0 }
            }
            pet
                .frame(width: 126, height: 150)
                .contentShape(Rectangle())
                .onHover { hoveringPet = $0 }
                .padding(.trailing, 6)
                .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: expanded)
        .onChange(of: expanded) { setExpanded($0) }
    }

    private var pet: some View {
        ZStack(alignment: .topTrailing) {
            FrierenSprite(mood: monitor.mood, hovered: hoveringPet)
            if monitor.liveSessions.contains(where: { $0.state == .waiting }) {
                Text("!")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 23, height: 23)
                    .background(Circle().fill(.orange))
                    .shadow(color: .orange.opacity(0.55), radius: 7)
                    .offset(x: -3, y: 5)
            }
        }
        .help("Hover to see agent sessions")
    }

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Agent sessions").font(.headline)
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { monitor.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help("Refresh")
                Button(action: quit) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }.buttonStyle(.plain).help("Quit Frieren Monitor")
            }
            .padding(14)
            Divider().opacity(0.4)
            if monitor.sessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "moon.zzz").font(.title2).foregroundStyle(.secondary)
                    Text("No local agent sessions").font(.subheadline)
                    Text("Claude Code · Codex · Cursor")
                        .font(.caption2.monospaced()).foregroundStyle(.tertiary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(monitor.sessions) { session in sessionRow(session) }
                    }.padding(9)
                }
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.16)))
        .shadow(color: .black.opacity(0.32), radius: 18, y: 8)
    }

    private func sessionRow(_ session: AgentSession) -> some View {
        Button { monitor.focus(session) } label: {
            HStack(spacing: 9) {
                Circle().fill(statusColor(session.state)).frame(width: 8, height: 8)
                    .shadow(color: statusColor(session.state).opacity(0.6), radius: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.displayName).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text("\(session.harness.label) · \(session.state.label)")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                if session.state != .finished {
                    Image(systemName: "arrow.up.forward.square").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10).fill(
                session.state == .waiting ? Color.orange.opacity(0.12) : Color.white.opacity(0.055)
            ))
        }
        .buttonStyle(.plain)
        .disabled(session.state == .finished)
        .help("Open \(session.harness.label)")
    }

    private var summary: String {
        let waiting = monitor.liveSessions.filter { $0.state == .waiting }.count
        if waiting > 0 { return "\(waiting) need\(waiting == 1 ? "s" : "") your input" }
        let running = monitor.liveSessions.count
        if running > 0 { return "\(running) active" }
        if monitor.sessions.contains(where: { $0.state == .finished }) { return "Recent work finished" }
        return "Frieren is resting"
    }

    private func statusColor(_ state: MonitorState) -> Color {
        switch state {
        case .running: return .cyan
        case .waiting: return .orange
        case .finished: return .green
        }
    }
}
