import AppKit
import SwiftUI

private struct PetAlert {
    let key: String
    let title: String
    let detail: String
    let icon: String
    let color: Color
    let celebratesCompletion: Bool
}

struct PetView: View {
    @ObservedObject var monitor: SessionMonitor
    @ObservedObject var motion: PetMotion
    let quit: () -> Void
    let setExpanded: (Bool) -> Void
    @State private var hoveringPet = false
    @State private var hoveringCard = false
    @State private var reactingToClick = false
    @State private var sayingHi = false
    @State private var reactionID = 0
    @State private var clickVariant = 0
    @State private var dismissedAlertKey: String?
    @State private var alertDismissID = 0
    @State private var showingRemoteSetup = false
    @State private var inactivityID = 0
    @State private var knownSessionStates: [String: MonitorState] = [:]

    private let inactivityInterval: TimeInterval = 2 * 60

    private var expanded: Bool {
        !motion.isDragging && (hoveringPet || hoveringCard)
    }
    private var panelExpanded: Bool {
        expanded || motion.isDragging || petAlert != nil || showingRemoteSetup
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear
            if expanded {
                sessionCard
                    .frame(width: 300, height: 218)
                    .padding(.trailing, 112)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .onHover {
                        hoveringCard = $0
                        if $0 { recordInteraction() }
                    }
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
                .onHover {
                    hoveringPet = $0
                    if $0 { recordInteraction() }
                }
                .padding(.trailing, 6)
                .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: panelExpanded)
        .onChange(of: panelExpanded) { setExpanded($0) }
        .onChange(of: currentAlertKey) { scheduleAlertDismissal(for: $0) }
        .onChange(of: motion.dragDirection) { direction in
            if direction != nil { recordInteraction() }
        }
        .onChange(of: monitor.sessions) { handleSessionChanges($0) }
        .onAppear {
            knownSessionStates = Dictionary(uniqueKeysWithValues: monitor.sessions.map { ($0.id, $0.state) })
            scheduleAlertDismissal(for: currentAlertKey)
            restartInactivityTimer()
        }
        .sheet(isPresented: $showingRemoteSetup) {
            RemoteSetupView {
                monitor.refresh()
                showingRemoteSetup = false
            }
        }
    }

    private var pet: some View {
        ZStack(alignment: .topTrailing) {
            FrierenSprite(
                mood: spriteMood,
                hovered: spriteHovered,
                travelDirection: motion.dragDirection,
                runningSessionCount: monitor.liveSessions.filter { $0.state == .running }.count,
                reactingToClick: reactingToClick,
                clickVariant: clickVariant,
                sayingHi: sayingHi
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
        .contextMenu {
            Button("Set Up Remote SSH…") {
                recordInteraction()
                NSApplication.shared.activate(ignoringOtherApps: true)
                showingRemoteSetup = true
            }
            Divider()
            Button("Quit Frieren Monitor", action: quit)
        }
        .help("Hover to see sessions · Right-click for remote SSH setup")
    }

    private func playClickReaction() {
        recordInteraction()
        reactionID += 1
        clickVariant = (clickVariant + 1) % 3
        let currentReaction = reactionID
        reactingToClick = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) {
            guard reactionID == currentReaction else { return }
            reactingToClick = false
        }
    }

    private func recordInteraction() {
        restartInactivityTimer()
    }

    private func handleSessionChanges(_ sessions: [AgentSession]) {
        let nextStates = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.state) })
        let hasNewSession = nextStates.keys.contains { knownSessionStates[$0] == nil }
        let hasNewFinishedSession = sessions.contains {
            $0.state == .finished && knownSessionStates[$0.id] != .finished
        }
        knownSessionStates = nextStates
        if hasNewSession || hasNewFinishedSession { restartInactivityTimer() }
    }

    private func restartInactivityTimer() {
        inactivityID += 1
        sayingHi = false
        scheduleHi(for: inactivityID)
    }

    private func scheduleHi(for id: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + inactivityInterval) {
            guard inactivityID == id else { return }
            sayingHi = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) {
                guard inactivityID == id else { return }
                sayingHi = false
            }
            scheduleHi(for: id)
        }
    }

    private var currentAlert: PetAlert? {
        if let waiting = monitor.liveSessions.first(where: { $0.state == .waiting }) {
            return PetAlert(
                key: "waiting-\(waiting.id)",
                title: "Prompt needed",
                detail: waiting.displayName,
                icon: "exclamationmark.bubble.fill",
                color: .orange,
                celebratesCompletion: false
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
                color: .green,
                celebratesCompletion: true
            )
        }
        return nil
    }

    private var currentAlertKey: String? { currentAlert?.key }

    private var petAlert: PetAlert? {
        guard let alert = currentAlert, alert.key != dismissedAlertKey else { return nil }
        return alert
    }

    private var showingCompletionAlert: Bool {
        !expanded && petAlert?.celebratesCompletion == true
    }

    private var spriteHovered: Bool {
        hoveringPet && currentAlert?.celebratesCompletion != true
    }

    private var spriteMood: PetMood {
        guard monitor.mood == .celebrating, !showingCompletionAlert else { return monitor.mood }
        if monitor.liveSessions.contains(where: { $0.state == .waiting }) { return .needsInput }
        if monitor.liveSessions.contains(where: { $0.state == .running }) { return .working }
        if !monitor.liveSessions.isEmpty { return .watching }
        return .sleeping
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
                Button {
                    recordInteraction()
                    monitor.refresh()
                } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help("Refresh")
                Button(action: quit) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }.buttonStyle(.plain).help("Quit Frieren Monitor")
            }
            .padding(14)
            Divider().opacity(0.4)
            if monitor.sessions.isEmpty && monitor.remoteHosts.allSatisfy(\.isOnline) {
                VStack(spacing: 8) {
                    Image(systemName: "moon.zzz").font(.title2).foregroundStyle(.secondary)
                    Text("No active agent sessions").font(.subheadline)
                    Text("Claude Code · Codex · Cursor")
                        .font(.caption2.monospaced()).foregroundStyle(.tertiary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(monitor.sessions) { session in sessionRow(session) }
                        ForEach(monitor.remoteHosts.filter { !$0.isOnline }) { host in
                            offlineHostRow(host)
                        }
                    }.padding(9)
                }
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.16)))
        .shadow(color: .black.opacity(0.32), radius: 18, y: 8)
    }

    private func sessionRow(_ session: AgentSession) -> some View {
        Button {
            recordInteraction()
            monitor.focus(session)
        } label: {
            HStack(spacing: 9) {
                Circle().fill(statusColor(session.state)).frame(width: 8, height: 8)
                    .shadow(color: statusColor(session.state).opacity(0.6), radius: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.displayName).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(sessionDetail(session))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                if session.state != .finished {
                    Image(systemName: session.isRemote ? "terminal" : "arrow.up.forward.square")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10).fill(
                session.state == .waiting ? Color.orange.opacity(0.12) : Color.white.opacity(0.055)
            ))
        }
        .buttonStyle(.plain)
        .disabled(session.state == .finished)
        .help(session.isRemote ? "Connect to \(session.remoteHost ?? "remote host") with SSH" : "Open \(session.harness.label)")
    }

    private func sessionDetail(_ session: AgentSession) -> String {
        if session.isRemote && !monitor.isSourceOnline(session) {
            return "\(session.harness.label) · Last seen \(session.state.label.lowercased()) · \(session.remoteHost ?? "remote")"
        }
        let base = "\(session.harness.label) · \(session.state.label)"
        return session.remoteHost.map { "\(base) · \($0)" } ?? base
    }

    private func offlineHostRow(_ host: RemoteHostStatus) -> some View {
        HStack(spacing: 9) {
            Circle().fill(Color.red).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(host.id).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text("Remote host · Offline")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "wifi.slash").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.08)))
        .help(host.error ?? "SSH connection failed")
    }

    private var summary: String {
        let waiting = monitor.liveSessions.filter { $0.state == .waiting }.count
        if waiting > 0 { return "\(waiting) need\(waiting == 1 ? "s" : "") your input" }
        let running = monitor.liveSessions.filter { $0.state == .running }.count
        if running > 0 { return "\(running) active" }
        let offline = monitor.remoteHosts.filter { !$0.isOnline }.count
        if offline > 0 { return "\(offline) remote host\(offline == 1 ? "" : "s") offline" }
        if monitor.sessions.contains(where: { $0.state == .finished }) { return "Recent work finished" }
        let idle = monitor.liveSessions.filter { $0.state == .idle }.count
        if idle > 0 { return "\(idle) idle" }
        return "Frieren is resting"
    }

    private func statusColor(_ state: MonitorState) -> Color {
        switch state {
        case .running: return .cyan
        case .waiting: return .orange
        case .finished: return .green
        case .idle: return .gray
        }
    }
}
