import SwiftUI
import AppKit
import MeetingHopKit

/// The onboarding card: what MeetingHop tells a user who has just installed
/// it, or who refused it access to their calendar.
///
/// Why this is a panel rather than a line in the menu-bar popover, which the
/// brief offered as the more honest home: the popover only exists once the
/// user goes looking for it, and the maintainer's rule is that every user sees
/// this once, whatever state their calendar is in. A message nobody is
/// obliged to open cannot satisfy "everyone is told once". The popover keeps
/// the same information as a permanent, non-nagging restatement — see
/// `MenuBarView`'s empty states — so nothing is only ever said here.
///
/// Why a second panel rather than a second state of `HUDView`: the card is
/// built by `Scheduler` around a meeting and is all countdown dial, rows and
/// Join buttons. A guidance message has none of those, and bending `HUDModel`
/// around a meetingless case would put a branch through every part of a view
/// whose whole job is meetings. The two share the window chrome (`HUDWindow`)
/// and nothing else.
///
/// The strings are `MeetingHopKit.GuidanceCopy`'s, the same way `HUDModel`
/// takes the card's wording from `Scheduler`: nothing here decides wording.
struct GuidanceView: View {
    let state: GuidanceState
    var onAction: () -> Void
    var onDismiss: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // `@State` is a macro in the macOS 26 SDK and its plugin ships with Xcode,
    // which this project does not build with — see `ViewLocal` in Support.swift.
    @StateObject private var appearedLocal = ViewLocal(false)

    private var appeared: Bool {
        get { appearedLocal.value }
        nonmutating set { appearedLocal.value = newValue }
    }

    /// Never the urgent rose: a refused permission is not a meeting about to
    /// start without the user, and colouring it the same way would spend the
    /// one alarm this app has on something that can wait.
    private var accent: Color { Brand.accent(scheme, urgent: false) }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(accent)
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(GuidanceCopy.title(state))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(GuidanceCopy.body(state))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button(GuidanceCopy.action(state), action: onAction)
                        .buttonStyle(GuidanceButtonStyle(accent: accent))
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier(AccessibilityID.Guidance.action)

                    Button(GuidanceCopy.dismiss, action: onDismiss)
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(AccessibilityID.Guidance.dismiss)

                    Spacer(minLength: 0)
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: HUDWindow.width)
        .overlay(
            // Inset by a full point, for the same reason the meeting card's
            // border is: the window mask clips at the very edge.
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(accent.opacity(0.30), lineWidth: 1.5)
                .padding(1)
        )
        .offset(y: appeared || reduceMotion ? 0 : -18)
        .opacity(appeared || reduceMotion ? 1 : 0)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { appeared = true }
        }
        // Two controls in one card, kept addressable as two identifiers
        // rather than merged into one element (KTD9/U5's pattern).
        .accessibilityElement(children: .contain)
    }

    private var icon: String {
        switch state {
        case .firstRun, .noCalendars: return "calendar"
        case .accessDenied: return "lock"
        }
    }
}

private struct GuidanceButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(
                    LinearGradient(
                        colors: [accent.opacity(0.92), accent],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            )
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

// MARK: - AppKit bridge

/// Wrapped the same way `HUDHostingController` is, and for the same reason:
/// the hosting view is built once and kept, so nothing restarts the entrance
/// animation. Unlike the card's, this one's content never changes after it is
/// built — the state it shows is decided before the panel exists — so there is
/// no `update(model:)` here to go with it.
@MainActor
final class GuidanceHostingController {
    private let hosting: NSHostingView<GuidanceView>

    init(state: GuidanceState, onAction: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.hosting = NSHostingView(
            rootView: GuidanceView(state: state, onAction: onAction, onDismiss: onDismiss)
        )
    }

    var view: NSView { hosting }
}
