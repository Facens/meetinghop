import SwiftUI
import AppKit
import MeetingHopKit

// MARK: - Brand

/// The palette is shared with AgentMenu so the two apps read as one family.
/// Only the app's own chrome uses it: the dial, the join button, the mark.
/// Everything else stays on system semantic colours, so a card in a window
/// tinted by the user's own accent choice still looks like macOS.
enum Brand {
    static let accentLight = Color(red: 0.839, green: 0.200, blue: 0.424)   // #D6336C
    static let accentDark  = Color(red: 1.000, green: 0.420, blue: 0.616)   // #FF6B9D

    /// Urgency pushes the same rose hotter rather than switching to AgentMenu's
    /// amber. That amber means "an agent will start without asking" over there;
    /// borrowing it here for "your meeting is ending" would give one colour two
    /// meanings across the pair.
    static let urgentLight = Color(red: 0.902, green: 0.114, blue: 0.325)
    static let urgentDark  = Color(red: 1.000, green: 0.298, blue: 0.478)

    static func accent(_ scheme: ColorScheme, urgent: Bool) -> Color {
        switch (scheme, urgent) {
        case (.dark, true):  return urgentDark
        case (.dark, false): return accentDark
        case (_, true):      return urgentLight
        case (_, false):     return accentLight
        }
    }
}

// MARK: - Model

/// One card's worth of state, translated from `MeetingHopKit.Card`. The
/// strings are built in the Kit; nothing here decides wording.
struct HUDModel: Sendable {
    /// One row: a meeting the user can join from this card. Several of them
    /// when two or more meetings start in the same slot.
    struct Item: Sendable, Identifiable {
        let meeting: UpcomingMeeting
        let context: String
        let primaryLabel: String

        var id: String { meeting.id }
        var title: String { meeting.title }
    }

    var items: [Item]
    /// Offers the card had no room for, named in a trailing line so the count
    /// on screen never silently disagrees with the menu bar.
    var hiddenCount: Int
    /// Shown above the rows when there is more than one: how many meetings,
    /// at what time. `nil` for a single offer, whose row says all of it.
    var headline: String?
    /// Minutes until the slot starts. Negative once it has started.
    var minutes: Int
    var isUrgent: Bool

    /// The dial's fill, 0 at the moment the card appears, 1 at start time.
    var progress: Double

    /// True once the card is a choice rather than a single offer. Rows get
    /// tighter type at that point: four rows at the single-offer size is a
    /// card half the height of the screen.
    var isMultiple: Bool { items.count > 1 }

    init(card: Card) {
        self.items = card.items.map {
            Item(meeting: $0.meeting, context: $0.context, primaryLabel: $0.primaryLabel)
        }
        self.hiddenCount = card.overflow.count
        self.headline = card.headline
        self.minutes = card.minutes
        self.isUrgent = card.urgent
        self.progress = card.progress
    }

    init(items: [Item], hiddenCount: Int = 0, headline: String? = nil, minutes: Int, isUrgent: Bool, progress: Double) {
        self.items = items
        self.hiddenCount = hiddenCount
        self.headline = headline
        self.minutes = minutes
        self.isUrgent = isUrgent
        self.progress = progress
    }
}

enum HUDAction: Sendable {
    /// Join one row's meeting. The others stay on the card.
    case join(UpcomingMeeting)
    /// The close button: answer the whole card at once.
    case dismissAll
}

// MARK: - The dial

/// The countdown is the card's subject, so it is the card's largest element
/// rather than a bar tucked under the text. The ring depletes; the numeral
/// inside is the remaining minutes.
private struct CountdownDial: View {
    let minutes: Int
    let progress: Double
    let accent: Color
    let reduceMotion: Bool

    private var label: String {
        if minutes > 0 { return "\(minutes)" }
        if minutes == 0 { return "now" }
        return "+\(-minutes)"
    }

    private var unit: String? {
        minutes > 0 ? "min" : (minutes < 0 ? "min ago" : nil)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(0.16), lineWidth: 3.5)

            Circle()
                .trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(
                    AngularGradient(
                        colors: [accent.opacity(0.55), accent],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.5), value: progress)

            VStack(spacing: -1) {
                Text(label)
                    .font(.system(size: minutes == 0 ? 15 : 24, weight: .light, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                if let unit {
                    Text(unit)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 58, height: 58)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            minutes > 0 ? "Starts in \(minutes) minutes"
                : (minutes == 0 ? "Starting now" : "Started \(-minutes) minutes ago")
        )
    }
}

// MARK: - Card

struct HUDView: View {
    @ObservedObject fileprivate var state: HUDState
    var onAction: (HUDAction) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // `@State` is a macro in the macOS 26 SDK and its plugin ships with Xcode,
    // which this project does not build with — see `ViewLocal` in Support.swift.
    @StateObject private var closeHoveredLocal = ViewLocal(false)
    @StateObject private var appearedLocal = ViewLocal(false)

    private var closeHovered: Bool {
        get { closeHoveredLocal.value }
        nonmutating set { closeHoveredLocal.value = newValue }
    }
    private var appeared: Bool {
        get { appearedLocal.value }
        nonmutating set { appearedLocal.value = newValue }
    }

    private var model: HUDModel { state.model }
    private var accent: Color { Brand.accent(scheme, urgent: model.isUrgent) }

    var body: some View {
        HStack(alignment: model.isMultiple ? .top : .center, spacing: 14) {
            CountdownDial(
                minutes: model.minutes,
                progress: model.progress,
                accent: accent,
                reduceMotion: reduceMotion
            )

            VStack(alignment: .leading, spacing: 0) {
                if let headline = model.headline {
                    Text(headline)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        // Clears the close button, which sits in the same
                        // corner and would otherwise land on the text.
                        .padding(.trailing, 26)
                        .padding(.bottom, 8)
                }

                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider().opacity(0.22).padding(.vertical, 7)
                    }
                    row(item)
                }

                if model.hiddenCount > 0 {
                    Text("+\(model.hiddenCount) more in the menu bar")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                }
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 18)
        .padding(.vertical, 14)
        .frame(width: 440)
        .overlay(
            // Inset by a full point: the window's mask clips at the very edge,
            // so a stroke sitting on the boundary loses its outer half and
            // reads as a hairline that does not follow the corner.
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(accent.opacity(model.isUrgent ? 0.55 : 0.30), lineWidth: 1.5)
                .padding(1)
        )
        .overlay(alignment: .topTrailing) { closeButton }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: model.isUrgent)
        // One orchestrated entrance: the card drops from under the screen edge.
        .offset(y: appeared || reduceMotion ? 0 : -18)
        .opacity(appeared || reduceMotion ? 1 : 0)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { appeared = true }
        }
        .accessibilityElement(children: .contain)
    }

    /// One offer. The single-offer card is this row next to the dial, laid out
    /// exactly as it was before the card could hold more than one.
    private func row(_ item: HUDModel.Item) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: model.isMultiple ? 13.5 : 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(item.context)
                    .font(.system(size: model.isMultiple ? 11 : 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 12)

            Button(item.primaryLabel) { onAction(.join(item.meeting)) }
                .buttonStyle(JoinButtonStyle(accent: accent, compact: model.isMultiple))
                // Only the first row can own the return key; the rest are
                // mouse or tab targets. A default action on every row would
                // make Return fire whichever one SwiftUI picked.
                .modifier(DefaultActionIfFirst(isFirst: item.id == model.items.first?.id))
                .accessibilityIdentifier(AccessibilityID.HUD.join(item))
        }
        // KTD9/U5's pattern: a row exposes more than one control (the title
        // text and the Join button), and `.contain` keeps them addressable
        // as two identifiers rather than one merged element.
        .accessibilityElement(children: .contain)
    }

    /// The only way to make the card go away, short of joining. It never
    /// auto-dismisses, so this control has to be permanently visible rather
    /// than revealed on hover.
    private var closeButton: some View {
        Button { onAction(.dismissAll) } label: {
            Image(systemName: "xmark")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(closeHovered ? Color.primary : Color.secondary)
                .frame(width: 18, height: 18)
                .background(
                    Circle().fill(Color.primary.opacity(closeHovered ? 0.12 : 0.06))
                )
        }
        .buttonStyle(.plain)
        .padding(.top, 9)
        .padding(.trailing, 9)
        .onHover { closeHovered = $0 }
        .accessibilityLabel(model.isMultiple ? "Dismiss all" : "Dismiss")
        .help(model.isMultiple ? "Dismiss all" : "Dismiss")
        .accessibilityIdentifier(AccessibilityID.HUD.close)
    }
}

/// `.keyboardShortcut(.defaultAction)` has no "sometimes" form, and a
/// `ForEach` row cannot branch on a modifier inline without changing the
/// view's type on every render. This applies it to one row only.
private struct DefaultActionIfFirst: ViewModifier {
    let isFirst: Bool

    func body(content: Content) -> some View {
        if isFirst {
            content.keyboardShortcut(.defaultAction)
        } else {
            content
        }
    }
}

private struct JoinButtonStyle: ButtonStyle {
    let accent: Color
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 13 : 16)
            .padding(.vertical, compact ? 5 : 7)
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

/// Wrapped rather than reconstructed on every update: rebuilding the hosting
/// view would restart the entrance animation each time the countdown ticks.
@MainActor
fileprivate final class HUDState: ObservableObject {
    @Published var model: HUDModel
    init(model: HUDModel) { self.model = model }
}

@MainActor
final class HUDHostingController {
    private let state: HUDState
    private let hosting: NSHostingView<HUDView>

    init(model: HUDModel, onAction: @escaping (HUDAction) -> Void) {
        let state = HUDState(model: model)
        self.state = state
        self.hosting = NSHostingView(rootView: HUDView(state: state, onAction: onAction))
    }

    var view: NSView { hosting }

    func update(model: HUDModel) {
        state.model = model
    }
}
