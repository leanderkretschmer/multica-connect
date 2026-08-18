import SwiftUI
import MulticaKit

/// Colour and spacing decisions in one place, so lanes, pills, and the call
/// screen agree without repeating literals.
enum Theme {
    /// Corner radius used by every card-shaped surface in the app.
    static let cardRadius: CGFloat = 16
    static let rowSpacing: CGFloat = 12
}

extension BoardLane {
    /// The lane's accent. Semantic colours keep the board legible in both
    /// appearances and under the accessibility contrast settings.
    var tint: Color {
        switch self {
        case .planned: .secondary
        case .ongoing: .blue
        case .staged: .purple
        case .finished: .green
        }
    }
}

extension IssuePriority {
    var symbolName: String? {
        switch self {
        case .none: nil
        case .low: "arrow.down"
        case .medium: "equal"
        case .high: "arrow.up"
        case .urgent: "exclamationmark.2"
        }
    }

    var tint: Color {
        switch self {
        case .none, .low: .secondary
        case .medium: .blue
        case .high: .orange
        case .urgent: .red
        }
    }
}

extension IssueStatus {
    var tint: Color {
        switch self {
        case .blocked: .red
        case .cancelled: .secondary
        default: BoardLane.lane(for: self).tint
        }
    }
}
