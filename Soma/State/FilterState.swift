import Foundation
import SwiftUI

// MARK: - Shared BP filter state (mirrors the web FilterBar, which sits above
// the Readings/Statistics/Charts tabs and filters all of them)

final class FilterState: ObservableObject {
    @Published var dateRange: DateRange = .month // web default is '1m'
    @Published var timeOfDay: TimeOfDay? = nil // nil = Any Time
}
