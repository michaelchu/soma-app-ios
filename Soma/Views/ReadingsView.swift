import SwiftUI

// MARK: - Readings tab (mirrors the web ReadingsTab mobile layout:
// category colour block, date + note icon, time · pulse, PP / MAP)

struct ReadingsView: View {
    @ObservedObject var store = BPStore.shared
    @EnvironmentObject var filters: FilterState
    @Binding var showQuickLog: Bool

    @State private var notesSession: BPSession? = nil

    private var filtered: [BPSession] {
        filterSessions(store.sessions, dateRange: filters.dateRange, timeOfDay: filters.timeOfDay)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // FilterBar (web: DateRangeTabs W/M/Q/All + time-of-day select)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(DateRange.allCases) { range in
                            FilterPill(label: range.label, isOn: filters.dateRange == range) {
                                filters.dateRange = range
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                }
                .padding(.top, 4)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterPill(label: "Any Time", isOn: filters.timeOfDay == nil) {
                            filters.timeOfDay = nil
                        }
                        ForEach(TimeOfDay.allCases) { t in
                            FilterPill(label: t.shortLabel, isOn: filters.timeOfDay == t) {
                                filters.timeOfDay = t
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                }
                .padding(.top, 8)

                if store.isLoading && store.sessions.isEmpty {
                    Spacer()
                    ProgressView("Loading blood pressure readings...")
                        .tint(SomaTheme.rose)
                    Spacer()
                } else if filtered.isEmpty {
                    Spacer()
                    Text("No readings yet")
                        .foregroundColor(SomaTheme.muted)
                    Spacer()
                } else {
                    List {
                        ForEach(filtered) { session in
                            ReadingRow(session: session)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(SomaTheme.background)
                                .listRowSeparator(.hidden)
                                .onTapGesture {
                                    if session.notes != nil { notesSession = session }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        Task { await store.deleteSession(session) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(SomaTheme.background)
                    .padding(.top, 6)
                }
            }
            .background(SomaTheme.background)
            .navigationTitle("Readings")
            .overlay(alignment: .bottomTrailing) {
                Button { showQuickLog = true } label: {
                    Image(systemName: "plus")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(SomaTheme.rose)
                        .clipShape(Circle())
                        .shadow(color: SomaTheme.rose.opacity(0.5), radius: 12)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 24)
            }
            .sheet(item: $notesSession) { session in
                NotesSheet(session: session)
                    .presentationDetents([.medium])
            }
            .refreshable {
                await store.load()
            }
        }
        .tint(SomaTheme.rose)
    }
}

struct FilterPill: View {
    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(SomaFont.regular(13))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isOn ? SomaTheme.rose.opacity(0.16) : Color(hex: "1b1b21"))
                .foregroundColor(isOn ? Color(hex: "fda4af") : SomaTheme.muted)
                .cornerRadius(999)
                .overlay(
                    RoundedRectangle(cornerRadius: 999)
                        .stroke(isOn ? SomaTheme.rose.opacity(0.45) : .clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct ReadingRow: View {
    let session: BPSession

    var body: some View {
        HStack(spacing: 0) {
            // Category colour block: systolic over diastolic (matches web)
            VStack(spacing: 2) {
                Text("\(session.systolic)")
                    .font(.custom("LINESeedJP-Bold", size: 20))
                Rectangle()
                    .fill(categoryColor.text)
                    .frame(width: 20, height: 1)
                    .opacity(0.3)
                Text("\(session.diastolic)")
                    .font(.custom("LINESeedJP-Bold", size: 20))
            }
            .foregroundColor(categoryColor.text)
            .frame(minWidth: 70)
            .padding(.vertical, 10)
            .background(categoryColor.bg)

            // Details
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(formatSessionDate(session.date))
                        .font(SomaFont.bold(15))
                        .foregroundColor(SomaTheme.text)
                    if session.notes != nil {
                        Image(systemName: "note.text")
                            .font(.caption2)
                            .foregroundColor(SomaTheme.muted)
                    }
                    if session.readingCount > 1 {
                        Text("\(session.readingCount)x")
                            .font(SomaFont.regular(11))
                            .foregroundColor(SomaTheme.muted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: "1b1b21"))
                            .cornerRadius(4)
                    }
                }
                HStack(spacing: 4) {
                    Text(session.timeOfDay.shortLabel)
                    if let pulse = session.pulse {
                        Text("·")
                        Text("\(pulse) bpm")
                    }
                }
                .font(SomaFont.regular(13))
                .foregroundColor(SomaTheme.muted)
            }
            .padding(.leading, 14)

            Spacer()

            // PP / MAP column (matches web)
            VStack(alignment: .trailing, spacing: 2) {
                Text("PP: \(session.pp)")
                Text("MAP: \(session.map)")
            }
            .font(SomaFont.regular(12))
            .foregroundColor(SomaTheme.muted)
            .padding(.trailing, 4)
        }
        .background(SomaTheme.background)
        .overlay(
            Rectangle()
                .fill(SomaTheme.border)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private var categoryColor: (bg: Color, text: Color) {
        switch session.category {
        case .normal:
            return (SomaTheme.categoryNormalBG, SomaTheme.categoryNormalText)
        case .hypertension:
            return (SomaTheme.categoryHypertensionBG, SomaTheme.categoryHypertensionText)
        case .hypertensionTreat:
            return (SomaTheme.categoryTreatBG, SomaTheme.categoryTreatText)
        }
    }
}

struct NotesSheet: View {
    let session: BPSession

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(session.notes ?? "No notes for this reading")
                    .font(SomaFont.regular(15))
                    .foregroundColor(SomaTheme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .background(SomaTheme.background)
            .navigationTitle("Notes · \(formatSessionDate(session.date)) \(session.timeOfDay.shortLabel)")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }
}
