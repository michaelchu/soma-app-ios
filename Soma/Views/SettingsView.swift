import SwiftUI

// MARK: - Settings: API connection, HealthKit sync, reminder time

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store = BPStore.shared
    @ObservedObject var reminders = ReminderManager.shared

    var isFirstRun: Bool = false
    var onDone: (() -> Void)? = nil

    @State private var token: String = KeychainHelper.loadToken() ?? ""
    @State private var showToken = false
    @State private var savedMessage: String?
    @State private var hkStatus: String = "Not connected"
    @State private var isSyncing = false
    @State private var syncMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if isFirstRun {
                    Section {
                        Text("Connect the app to your Soma server to load your blood pressure history.")
                            .font(SomaFont.regular(14))
                            .foregroundColor(SomaTheme.muted)
                    }
                }

                Section("Soma API") {
                    Text("Connected to use-soma.vercel.app")
                        .font(SomaFont.regular(13))
                        .foregroundColor(SomaTheme.muted)
                    HStack {
                        if showToken {
                            TextField("API token", text: $token)
                        } else {
                            SecureField("API token", text: $token)
                        }
                        Button {
                            showToken.toggle()
                        } label: {
                            Image(systemName: showToken ? "eye.slash" : "eye")
                        }
                    }
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    Button("Save & Connect") {
                        saveAPIConfig()
                    }
                    .tint(SomaTheme.rose)
                    if let savedMessage {
                        Text(savedMessage)
                            .font(SomaFont.regular(13))
                            .foregroundColor(SomaTheme.muted)
                    }
                }

                Section("Apple Health") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(hkStatus)
                            .foregroundColor(SomaTheme.muted)
                    }
                    if hkStatus != "Connected" {
                        Button("Connect Apple Health") {
                            Task {
                                do {
                                    try await HealthKitManager.shared.requestAuthorization()
                                    hkStatus = "Connected"
                                } catch {
                                    hkStatus = "Denied"
                                }
                            }
                        }
                    } else {
                        // iOS doesn't let apps revoke HealthKit access themselves;
                        // the user does it in Settings.
                        Button("Manage Health permissions in Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .foregroundColor(SomaTheme.muted)
                    }
                    Button("Import new Health readings into Soma") {
                        Task {
                            isSyncing = true
                            syncMessage = nil
                            let result = await store.syncFromHealthKit()
                            syncMessage = "Imported \(result.imported), skipped \(result.skipped) already in Soma."
                            isSyncing = false
                        }
                    }
                    .disabled(isSyncing)
                    if isSyncing { ProgressView().tint(SomaTheme.rose) }
                    if let syncMessage {
                        Text(syncMessage)
                            .font(SomaFont.regular(13))
                            .foregroundColor(SomaTheme.muted)
                    }
                }

                Section("Reminder") {
                    DatePicker("Time", selection: Binding(
                        get: { reminders.time },
                        set: { reminders.time = $0 }
                    ), displayedComponents: .hourAndMinute)
                }

                Section {
                    Text("Soma iOS v1 · BP only")
                        .font(SomaFont.regular(12))
                        .foregroundColor(SomaTheme.muted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(SomaTheme.background)
            .navigationTitle(isFirstRun ? "Connect to Soma" : "Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if isFirstRun {
                        Button("Done") {
                            saveAPIConfig()
                            onDone?()
                        }
                        .disabled(token.isEmpty)
                    } else {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .onAppear {
                switch HealthKitManager.shared.authorizationStatus() {
                case .authorized: hkStatus = "Connected"
                case .denied: hkStatus = "Denied"
                case .notDetermined: hkStatus = "Not connected"
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(SomaTheme.rose)
    }

    private func saveAPIConfig() {
        _ = KeychainHelper.saveToken(token.trimmingCharacters(in: .whitespacesAndNewlines))
        Task {
            await store.load()
            if store.errorMessage == nil {
                savedMessage = "Connected — \(store.sessions.count) sessions loaded."
            } else {
                savedMessage = store.errorMessage
            }
        }
    }
}
