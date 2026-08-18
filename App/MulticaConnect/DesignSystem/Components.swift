import SwiftUI
import MulticaKit

/// A small capsule label — status, priority, lane count.
struct Pill: View {
    let text: String
    var symbolName: String?
    var tint: Color = .secondary

    var body: some View {
        Label {
            Text(text)
        } icon: {
            if let symbolName {
                Image(systemName: symbolName)
            }
        }
        .labelStyle(.titleAndIcon)
        .font(.caption.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.12), in: .capsule)
    }
}

/// The three states every remote list can be in, in one place, so no screen
/// ships a happy path only.
struct LoadStateView<Content: View>: View {
    let isLoading: Bool
    let error: String?
    let isEmpty: Bool
    let emptyTitle: String
    let emptyMessage: String
    var emptySymbol: String = "tray"
    var retry: (() -> Void)?
    @ViewBuilder var content: () -> Content

    var body: some View {
        if let error {
            ContentUnavailableView {
                Label("Something went wrong", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                if let retry {
                    Button("Try again", action: retry)
                        .buttonStyle(.borderedProminent)
                }
            }
        } else if isLoading && isEmpty {
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isEmpty {
            ContentUnavailableView {
                Label(emptyTitle, systemImage: emptySymbol)
            } description: {
                Text(emptyMessage)
            }
        } else {
            content()
        }
    }
}

/// The circular button that starts and ends a call.
struct CallButton: View {
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isActive ? "phone.down.fill" : "mic.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(isActive ? Color.red : Color.accentColor, in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isActive ? "End call" : "Start call")
        .sensoryFeedback(isActive ? .stop : .start, trigger: isActive)
    }
}
