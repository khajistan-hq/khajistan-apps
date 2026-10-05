import Foundation
import Observation

private enum DefaultsKey {
    static let extendedAtlas = "kj.extendedAtlas"
    static let startTab = "kjtab"
    static let skin = "kjskin"
}

@MainActor @Observable
final class AppModel {
    var skin: Skin
    /// The root screen on show. The launch argument `-kjtab <name>` picks the one a UI test starts on.
    var section: Section
    let auth: AuthStore
    let receiver: ReceiverStore
    let transmission: TransmissionStore
    /// The wing wipes and the sign-on ident. One player for the life of the app.
    let clips = StationClips()

    /// "Beyond the atlas", persisted on the device and off by default. The value lives in
    /// UserDefaults, so the registrar is told by hand when it is read and when it changes.
    var extendedAtlas: Bool {
        get {
            access(keyPath: \.extendedAtlas)
            return UserDefaults.standard.bool(forKey: DefaultsKey.extendedAtlas)
        }
        set {
            withMutation(keyPath: \.extendedAtlas) {
                UserDefaults.standard.set(newValue, forKey: DefaultsKey.extendedAtlas)
            }
        }
    }

    init() {
        let auth = AuthStore()
        self.auth = auth
        self.receiver = ReceiverStore()
        self.transmission = TransmissionStore(auth: auth)
        // `-kjskin grove` holds one skin for a UI test, which otherwise sees only the hour's.
        let pinned = UserDefaults.standard.string(forKey: DefaultsKey.skin).flatMap(Skin.init(rawValue:))
        self.skin = pinned ?? Skin.current(at: Date(), calendar: .current)
        // Read once. Xcode turns the launch arguments "-kjtab transmission" into this default.
        switch UserDefaults.standard.string(forKey: DefaultsKey.startTab) {
        case "transmission": self.section = .transmission
        case "account": self.section = .account
        default: self.section = .receiver
        }
        if pinned == nil { watchTheSky() }
    }

    /// Looks at the clock once a minute and changes the skin when the hour crosses a band.
    private func watchTheSky() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self else { return }
                let next = Skin.current(at: Date(), calendar: .current)
                if next != self.skin { self.skin = next }
            }
        }
    }
}
