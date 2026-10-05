import SwiftUI

// MARK: - Root tab navigation (native iOS chrome around Soma content)

struct ContentView: View {
    @StateObject private var store = BPStore.shared
    @StateObject private var filters = FilterState()
    @State private var showQuickLog = false

    var body: some View {
        TabView {
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
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .tint(SomaTheme.rose)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showQuickLog) {
            QuickLogSheet()
                .environmentObject(store)
        }
        .task {
            await store.load()
        }
    }
}
