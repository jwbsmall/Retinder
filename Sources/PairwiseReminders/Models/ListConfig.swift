import Foundation
import SwiftData

/// Persists a record per EKCalendar so SwiftData can track which lists the app has seen.
/// Write-back options are chosen at apply-time (in ResultsView) rather than stored here.
@Model final class ListConfig {

    /// EKCalendar.calendarIdentifier.
    var calendarIdentifier: String

    init(calendarIdentifier: String) {
        self.calendarIdentifier = calendarIdentifier
    }
}
