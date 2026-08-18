import SwiftUI

struct RemoteSetupView: View {
    let completed: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sshTarget = ""
    @State private var displayName = ""
    @State private var identityFile = ""
    @State private var installing = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field { case sshTarget, displayName, identityFile }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Set Up Remote SSH").font(.title2.bold())
                Text("Frieren will install a small collector and add lifecycle hooks without replacing existing agent settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("SSH target")
                    TextField("dev-vm or user@example.com", text: $sshTarget)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .sshTarget)
                }
                GridRow {
                    Text("Display name")
                    TextField("Optional — defaults to SSH target", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .displayName)
                }
                GridRow {
                    Text("Identity file")
                    TextField("Optional — uses ~/.ssh/config by default", text: $identityFile)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .identityFile)
                }
            }

            Text("SSH must already work with a key or ssh-agent. New host keys are accepted on first connection; changed keys are rejected.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let resultMessage {
                Label(resultMessage, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)
            HStack {
                if installing {
                    ProgressView().controlSize(.small)
                    Text("Connecting and installing…").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button(resultMessage == nil ? "Cancel" : "Close") {
                    if resultMessage == nil { dismiss() } else { completed() }
                }
                .keyboardShortcut(.cancelAction)
                .disabled(installing)
                if resultMessage == nil {
                    Button("Set Up") { install() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(installing || sshTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(22)
        .frame(width: 510, height: 340)
        .onAppear {
            NSApplication.shared.activate(ignoringOtherApps: true)
            focusedField = .sshTarget
        }
    }

    private func install() {
        installing = true
        errorMessage = nil
        RemoteSetupService.install(
            target: sshTarget,
            name: displayName,
            identityFile: identityFile
        ) { result in
            installing = false
            switch result {
            case .success(let message): resultMessage = message
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
    }
}
