import SwiftUI

// MARK: - Root tab navigation (native iOS chrome around Soma content)

struct ContentView: View {
    @StateObject private var store = BPStore.shared
    @StateObject private var reminders = ReminderManager.shared
    @StateObject private var filters = FilterState()
    @State private var showQuickLog = false
    @State private var showSettings = false

    var body: some View {
        TabView {
            TodayView(showQuickLog: $showQuickLog, showSettings: $showSettings)
                .tabItem {
                    Label("Today", systemImage: "house")
                }
            ReadingsView(showQuickLog: $showQuickLog)
                .environmentObject(filters)
                .tabItem {
                    Label("Readings", systemImage: "list.bullet")
                }
            StatisticsView()
                .environmentObject(filters)
                .tabItem {
                    Label("Stats", systemImage: "chart.bar")
                }
            ChartsView()
                .environmentObject(filters)
                .tabItem {
                    Label("Charts", systemImage: "chart.line.uptrend.xyaxis")
                }
        }
        .tint(SomaTheme.rose)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showQuickLog) {
            QuickLogSheet()
                .environmentObject(store)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .task {
            await store.load()
        }
        .onChange(of: showSettings) { _, isPresented in
            if !isPresented {
                Task { await store.load() }
            }
        }
    }
}
