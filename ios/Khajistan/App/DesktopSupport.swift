#if targetEnvironment(macCatalyst)
import UIKit

/// Keep the Receiver map and its controls usable in a resizable Mac window.
@MainActor
enum DesktopSupport {
    static func configureWindows() {
        for scene in UIApplication.shared.connectedScenes {
            guard let window = scene as? UIWindowScene else { continue }
            window.sizeRestrictions?.minimumSize = CGSize(width: 800, height: 600)
        }
    }
}
#endif
