import Foundation
import SwiftUI

// MARK: - Shared BP filter state

final class FilterState: ObservableObject {
    @Published var dateRange: DateRange = .month
    @Published var lastPresetDateRange: DateRange = .month
    @Published var customStartDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @Published var customEndDate = Date()
    @Published var timeOfDay: TimeOfDay? = nil
}

struct BPFilterBar: View {
    @ObservedObject var filters: FilterState

    @State private var isShowingCustomRange = false
    @State private var draftStartDate = Date()
    @State private var draftEndDate = Date()

    private var presetDateRangeSelection: Binding<DateRange> {
        Binding(
            get: {
                filters.dateRange == .custom
                    ? filters.lastPresetDateRange
                    : filters.dateRange
            },
            set: { range in
                filters.lastPresetDateRange = range
                filters.dateRange = range
            }
        )
    }

    private var selectedTimeLabel: String {
        filters.timeOfDay?.shortLabel ?? "Any Time"
    }

    var body: some View {
        VStack(spacing: 8) {
            Picker("Date Range", selection: presetDateRangeSelection) {
                ForEach(DateRange.presets) { range in
                    Text(range.label).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .opacity(filters.dateRange == .custom ? 0.6 : 1)
            .padding(.horizontal, 18)

            HStack(spacing: 8) {
                Menu {
                    Button {
                        filters.timeOfDay = nil
                    } label: {
                        if filters.timeOfDay == nil {
                            Label("Any Time", systemImage: "checkmark")
                        } else {
                            Text("Any Time")
                        }
                    }

                    ForEach(TimeOfDay.allCases) { timeOfDay in
                        Button {
                            filters.timeOfDay = timeOfDay
                        } label: {
                            if filters.timeOfDay == timeOfDay {
                                Label(timeOfDay.shortLabel, systemImage: "checkmark")
                            } else {
                                Text(timeOfDay.shortLabel)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                        Text(selectedTimeLabel)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .font(SomaFont.regular(13))
                    .foregroundStyle(SomaTheme.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color(hex: "1b1b21"))
                    .clipShape(Capsule())
                }

                FilterPill(label: "Custom Dates", isOn: filters.dateRange == .custom) {
                    presentCustomRange()
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
        }
        .padding(.top, 4)
        .sheet(isPresented: $isShowingCustomRange) {
            CustomDateRangeSheet(
                startDate: $draftStartDate,
                endDate: $draftEndDate
            ) {
                filters.customStartDate = draftStartDate
                filters.customEndDate = draftEndDate
                filters.dateRange = .custom
            }
            .presentationDetents([.medium])
        }
    }

    private func presentCustomRange() {
        draftStartDate = filters.customStartDate
        draftEndDate = filters.customEndDate
        isShowingCustomRange = true
    }
}

private struct CustomDateRangeSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var startDate: Date
    @Binding var endDate: Date
    let onApply: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Start",
                        selection: $startDate,
                        in: ...endDate,
                        displayedComponents: .date
                    )
                    DatePicker(
                        "End",
                        selection: $endDate,
                        in: startDate...Date(),
                        displayedComponents: .date
                    )
                } footer: {
                    Text("Readings on both the start and end dates are included.")
                }
            }
            .navigationTitle("Custom Date Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply()
                        dismiss()
                    }
                }
            }
        }
    }
}
