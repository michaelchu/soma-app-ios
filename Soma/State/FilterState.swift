import Foundation
import SwiftUI

// MARK: - Shared BP filter state (mirrors the web FilterBar, which sits above
// the Readings/Statistics/Charts tabs and filters all of them)

final class FilterState: ObservableObject {
    @Published var dateRange: DateRange = .month // web default is '1m'
    @Published var timeOfDay: TimeOfDay? = nil // nil = Any Time
}

struct BPFilterBar: View {
    @ObservedObject var filters: FilterState

    var body: some View {
        VStack(spacing: 8) {
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterPill(label: "Any Time", isOn: filters.timeOfDay == nil) {
                        filters.timeOfDay = nil
                    }
                    ForEach(TimeOfDay.allCases) { timeOfDay in
                        FilterPill(label: timeOfDay.shortLabel, isOn: filters.timeOfDay == timeOfDay) {
                            filters.timeOfDay = timeOfDay
                        }
                    }
                }
                .padding(.horizontal, 18)
            }
        }
        .padding(.top, 4)
    }
}
