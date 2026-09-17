import CoreGraphics
import AppKit

/// Diagnostics only. The app itself identifies the previous meeting by its
/// window owner name, which needs no permission.
///
/// Window *numbers* and owner names are readable without the Screen Recording
/// permission; only window *titles* would require it. We deliberately stay on
/// this side of the line.
enum ZoomWindows {
    static func meetingWindowNumbers() -> Set<Int> {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var result = Set<Int>()
        for w in list {
            guard let owner = w[kCGWindowOwnerName as String] as? String,
                  owner.lowercased().contains("zoom"),
                  let number = w[kCGWindowNumber as String] as? Int,
                  let bounds = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"], let height = bounds["Height"]
            else { continue }
            // Ignore toolbars and the small floating controls.
            guard width > 600, height > 400 else { continue }
            result.insert(number)
        }
        return result
    }
}
