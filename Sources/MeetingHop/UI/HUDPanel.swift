import AppKit
import SwiftUI
import MeetingHopKit

/// The floating card's window. Non-activating, so clicking the card never
/// pulls focus away from the meeting the user is in.
final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

enum HUDWindow {

    static let width: CGFloat = 440
    static let cornerRadius: CGFloat = 18

    /// Builds the panel around a hosted card.
    ///
    /// The blur has to come from an `NSVisualEffectView` in `behindWindow`
    /// mode. SwiftUI's `.ultraThinMaterial` blends *within* its own window, so
    /// in a borderless panel it has nothing to sample and renders as flat grey
    /// with opaque corners. The window shadow is likewise AppKit's: a SwiftUI
    /// shadow is clipped at the window bounds, so it never appears at all.
    ///
    /// `identifier` is required rather than defaulted to `HUD.panel`: two
    /// different panels are built from this one function now (the meeting card
    /// and the onboarding card), and `findByIdentifier` in
    /// `harness/guest/ax.applescript` returns the first window it walks to —
    /// so a second panel that silently inherited the card's identifier would
    /// make a Join click land on whichever of the two the walk reached first.
    @MainActor
    static func make(hosting: NSView, identifier: String) -> HUDPanel {
        let frame = NSRect(x: 0, y: 0, width: width, height: fittingHeight(of: hosting))

        let panel = HUDPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isMovableByWindowBackground = true
        // AppKit derives the shadow from the content's alpha, so the masked
        // effect view below gives it the rounded shape for free.
        panel.hasShadow = true
        // KTD9: the panel is a borderless NSPanel, not a SwiftUI view, so
        // System Events needs its own identifier to find it as a "window"
        // at all — the SwiftUI content's own identifiers are only reachable
        // once the panel itself has been.
        panel.setAccessibilityIdentifier(identifier)

        let blur = NSVisualEffectView(frame: frame)
        // .hudWindow, not .popover: a floating card over someone's work should read
        // like the system's own volume and brightness overlays, which are dark and
        // clearly not part of the app underneath. .popover is a light grey sheet.
        blur.material = .hudWindow
        // Dark whatever the system theme is. A card that follows the theme is a
        // light grey sheet on a light desktop, indistinguishable from the window
        // under it; the system's own overlays get away with that because they
        // are momentary, and this one sits there until it is answered.
        blur.appearance = NSAppearance(named: .darkAqua)
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]
        // A layer corner radius does not survive here: NSVisualEffectView
        // rebuilds its own layer, and the square corners come back with a
        // rectangular window shadow behind them. maskImage is the supported
        // way to round it, and the shadow follows the mask's alpha.
        blur.maskImage = roundedMask(radius: cornerRadius)

        hosting.frame = frame
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        blur.addSubview(hosting)

        panel.contentView = blur
        return panel
    }

    /// A resizable rounded-rectangle mask: nine-part scaling keeps the corner
    /// radius fixed while the middle stretches to the card's height.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    /// Resizes the panel to the card's current height.
    ///
    /// A card is no longer a fixed height: a double booking renders a row per
    /// meeting, and answering one takes a row away again. Without this, the
    /// window keeps whatever height it had when it was created — the extra
    /// rows are clipped off the bottom, or an answered row leaves a gap — and
    /// `position` then places the stale height under the menu bar.
    @MainActor
    static func fit(_ panel: NSWindow, hosting: NSView) {
        let height = fittingHeight(of: hosting)
        guard abs(panel.frame.height - height) > 0.5 else { return }
        panel.setContentSize(NSSize(width: width, height: height))
    }

    /// 86 is the floor rather than the height: `fittingSize` is zero until the
    /// hosting view has laid out, and a zero-height panel is invisible.
    @MainActor
    private static func fittingHeight(of hosting: NSView) -> CGFloat {
        hosting.layoutSubtreeIfNeeded()
        return max(hosting.fittingSize.height, 86)
    }

    /// Top centre of the active screen, just under the menu bar.
    @MainActor
    static func position(_ panel: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.maxY - size.height - 22))
    }
}
