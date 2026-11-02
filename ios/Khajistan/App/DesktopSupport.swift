#if targetEnvironment(macCatalyst)
import UIKit
import SwiftUI

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

/// A reader, player or form must be closed before a Mac menu moves to another room.
/// Otherwise the root's retained tabs can change underneath a still-presented local cover.
private struct MacNavigationGuard: ViewModifier {
    let isActive: Bool
    let model: AppModel
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear(perform: update)
            .onChange(of: isActive) { update() }
            .onDisappear { model.menuNavigationLocks.remove(id) }
    }

    private func update() {
        if isActive { model.menuNavigationLocks.insert(id) }
        else { model.menuNavigationLocks.remove(id) }
    }
}
#endif

import SwiftUI

extension View {
    @ViewBuilder
    func blocksMacNavigation(_ model: AppModel, while isActive: Bool = true) -> some View {
        #if targetEnvironment(macCatalyst)
        modifier(MacNavigationGuard(isActive: isActive, model: model))
        #else
        self
        #endif
    }
}
