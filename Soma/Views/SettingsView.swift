import SwiftUI

// MARK: - Settings: Apple Health connection and reminder time

struct SettingsView: View {
    @ObservedObject var store = BPStore.shared
    @ObservedObject var reminders = ReminderManager.shared

    var isFirstRun: Bool = false
    var onDone: (() -> Void)? = nil

    @State private var healthStatus = "Not connected"
    @State private var isWorking = false
    @State private var message: String?

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
                    }

                    if isWorking {
                        ProgressView().tint(SomaTheme.rose)
                    }

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
