import SwiftUI

// MARK: - Settings: Apple Health connection and reminder time

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store = BPStore.shared
    @ObservedObject var reminders = ReminderManager.shared

    var isFirstRun: Bool = false
    var onDone: (() -> Void)? = nil

    @State private var healthStatus = "Not connected"
    @State private var isWorking = false
    @State private var message: String?
    #if DEBUG
    @State private var isRepairingHealthData = false
    #endif

    var body: some View {
        NavigationStack {
            Form {
                if isFirstRun {
                    Section {
                        Text("Soma reads and stores your blood pressure history in Apple Health.")
                            .font(SomaFont.regular(14))
                            .foregroundColor(SomaTheme.muted)
                    }
                }

                Section("Apple Health") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(healthStatus)
                            .foregroundColor(SomaTheme.muted)
                    }

                    if healthStatus != "Connected" {
                        Button("Connect Apple Health") {
                            Task { await connectToHealth() }
                        }
                        .disabled(isWorking)
                    } else {
                        Button("Refresh from Apple Health") {
                            Task {
                                isWorking = true
                                message = nil
                                await store.load()
                                message = store.errorMessage ?? "Loaded \(store.sessions.count) readings."
                                isWorking = false
                            }
                        }
                        .disabled(isWorking)

                        Button("Manage Health permissions in Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .foregroundColor(SomaTheme.muted)
                    }

                    #if DEBUG
                    Button("Export Vercel seed data") {
                        Task {
                            isRepairingHealthData = true
                            message = nil
                            do {
                                let url = try await store.exportVercelSeedData()
                                message = "Exported seed data to \(url.lastPathComponent)."
                            } catch {
                                message = "Seed export failed: \(error.localizedDescription)"
                            }
                            isRepairingHealthData = false
                        }
                    }
                    .disabled(isWorking || isRepairingHealthData)

                    Button("Repair Apple Health from Vercel", role: .destructive) {
                        Task {
                            isRepairingHealthData = true
                            message = nil
                            do {
                                let result = try await store.repairHealthKitFromVercel()
                                message = "Deleted \(result.deleted) Soma samples and imported \(result.imported) averaged sessions."
                            } catch {
                                message = "Repair failed: \(error.localizedDescription)"
                            }
                            isRepairingHealthData = false
                        }
                    }
                    .disabled(isWorking || isRepairingHealthData)
                    #endif

                    #if DEBUG
                    if isWorking || isRepairingHealthData {
                        ProgressView().tint(SomaTheme.rose)
                    }
                    #else
                    if isWorking {
                        ProgressView().tint(SomaTheme.rose)
                    }
                    #endif
                    if let message {
                        Text(message)
                            .font(SomaFont.regular(13))
                            .foregroundColor(SomaTheme.muted)
                    }
                }

                Section("Reminder") {
                    DatePicker(
                        "Time",
                        selection: Binding(
                            get: { reminders.time },
                            set: { reminders.time = $0 }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                }

                Section {
                    Text("Soma iOS v1 · Apple Health")
                        .font(SomaFont.regular(12))
                        .foregroundColor(SomaTheme.muted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(SomaTheme.background)
            .navigationTitle(isFirstRun ? "Connect Apple Health" : "Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isFirstRun {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .onAppear {
                switch HealthKitManager.shared.authorizationStatus() {
                case .authorized:
                    healthStatus = "Connected"
                case .denied:
                    healthStatus = "Denied"
                case .notDetermined:
                    healthStatus = "Not connected"
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(SomaTheme.rose)
    }

    private func connectToHealth() async {
        isWorking = true
        message = nil
        do {
            try await HealthKitManager.shared.requestAuthorization()
            healthStatus = "Connected"
            UserDefaults.standard.set(true, forKey: "soma.hasConnectedAppleHealth")
            await store.load()
            if let errorMessage = store.errorMessage {
                message = errorMessage
            } else {
                message = "Loaded \(store.sessions.count) readings."
                onDone?()
            }
        } catch {
            healthStatus = "Denied"
            message = error.localizedDescription
        }
        isWorking = false
    }
}
