import AppKit
import CoreGraphics

/// Whether Zoom is presenting right now.
///
/// This is the only thing the app needs to know about Zoom, and it is read
/// from window *owner* names, which carry no permission requirement. Window
/// titles would need Accessibility, and the Accessibility route was removed:
/// the only other thing it bought was choosing between two words on a button.
enum ZoomPresence {

    /// Zoom's screen-share frame belongs to a helper process of its own, so a
    /// window owned by it on screen means a share is in progress.
    private static let shareOwners = ["cpthost", "zoom share"]

    static var isSharingScreen: Bool {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return list.contains { window in
            guard let owner = (window[kCGWindowOwnerName as String] as? String)?.lowercased() else {
                return false
            }
            return shareOwners.contains { owner.contains($0) }
        }
    }
}
