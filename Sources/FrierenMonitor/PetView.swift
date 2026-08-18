import AppKit
import SwiftUI

private struct PetAlert {
    let key: String
    let title: String
    let detail: String
    let icon: String
    let color: Color
}

struct PetView: View {
    @ObservedObject var monitor: SessionMonitor
    @ObservedObject var motion: PetMotion
    let quit: () -> Void
    let setExpanded: (Bool) -> Void
    @State private var hoveringPet = false
    @State private var hoveringCard = false
    @State private var reactingToClick = false
    @State private var reactionID = 0
    @State private var clickVariant = 0
    @State private var dismissedAlertKey: String?
    @State private var alertDismissID = 0

    private var expanded: Bool { hoveringPet || hoveringCard }
    private var panelExpanded: Bool { expanded || petAlert != nil }

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
            } else if let alert = petAlert {
                alertBubble(alert)
                    .frame(width: 230)
                    .padding(.trailing, 108)
                    .padding(.bottom, 102)
                    .transition(.scale(scale: 0.85, anchor: .bottomTrailing).combined(with: .opacity))
            }
            pet
                .frame(width: 126, height: 150)
                .contentShape(Rectangle())
                .onHover { hoveringPet = $0 }
                .padding(.trailing, 6)
                .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: panelExpanded)
        .onChange(of: panelExpanded) { setExpanded($0) }
        .onChange(of: currentAlertKey) { scheduleAlertDismissal(for: $0) }
        .onAppear { scheduleAlertDismissal(for: currentAlertKey) }
    }

    private var pet: some View {
        ZStack(alignment: .topTrailing) {
            FrierenSprite(
                mood: monitor.mood,
                hovered: hoveringPet,
                travelDirection: motion.dragDirection,
                runningSessionCount: monitor.liveSessions.filter { $0.state == .running }.count,
                reactingToClick: reactingToClick,
                clickVariant: clickVariant
            )
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
        .simultaneousGesture(TapGesture().onEnded { playClickReaction() })
        .help("Hover to see agent sessions · Click to interact")
    }

    private func playClickReaction() {
        reactionID += 1
        clickVariant = (clickVariant + 1) % 3
        let currentReaction = reactionID
        reactingToClick = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) {
            guard reactionID == currentReaction else { return }
            reactingToClick = false
        }
    }

    private var currentAlert: PetAlert? {
        if let waiting = monitor.liveSessions.first(where: { $0.state == .waiting }) {
            return PetAlert(
                key: "waiting-\(waiting.id)",
                title: "Prompt needed",
                detail: waiting.displayName,
                icon: "exclamationmark.bubble.fill",
                color: .orange
            )
        }
        if let finished = monitor.sessions.first(where: {
            $0.state == .finished
                && Date().timeIntervalSince($0.updatedAt) < SessionMonitor.celebrationWindow
        }) {
            return PetAlert(
                key: "finished-\(finished.id)",
                title: "Session finished!",
                detail: finished.displayName,
                icon: "checkmark.circle.fill",
                color: .green
            )
        }
        return nil
    }

    private var currentAlertKey: String? { currentAlert?.key }

    private var petAlert: PetAlert? {
        guard let alert = currentAlert, alert.key != dismissedAlertKey else { return nil }
        return alert
    }

    private func scheduleAlertDismissal(for key: String?) {
        alertDismissID += 1
        let dismissalID = alertDismissID
        dismissedAlertKey = nil
        guard let key else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard alertDismissID == dismissalID else { return }
            dismissedAlertKey = key
        }
    }

    private func alertBubble(_ alert: PetAlert) -> some View {
        HStack(spacing: 10) {
            Image(systemName: alert.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(alert.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Text(alert.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(alert.color.opacity(0.55), lineWidth: 1.5)
        }
        .shadow(color: alert.color.opacity(0.25), radius: 12, y: 5)
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
