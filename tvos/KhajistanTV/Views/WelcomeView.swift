import AVFoundation
import SwiftUI

/// What the app is, said once, the first time it opens (owner, 2026-11-20: "a landing page ... to
/// intro what the app is", with the Higgsfield clips the station already uses). The pigeon's
/// sign-on ident plays once and the jewelled wordmark loops after it, at the right; the text is
/// at the left. No black (owner, 2026-11-20: "no black backgroiund"): each clip is rendered onto
/// each skin's ground (scripts/welcome/render_welcome.py), so the bird and the wordmark sit on the
/// page itself, and the file for the skin on screen is the one played. One button, Start, and Menu does the same.
///
/// Both clips are house chrome under the 2026-10-04 and 2026-11-15 Higgsfield rulings (the pigeon,
/// and the wordmark loops), never a holding. They play muted.
struct WelcomeView: View {
    let done: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reel = WelcomeReel()
    @FocusState private var startFocused: Bool

    static let pictureSize = CGSize(width: 1040, height: 585)

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 36) {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Khajistan")
                        .kjDisplay()
                        .accessibilityAddTraits(.isHeader)
                    Text("Live television and radio from the Indus to the Maghreb, and Khajistan's own station, which plays tapes, films and records from the archive.")
                        .kjBody()
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(sections, id: \.0) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(section.0.title).kjName()
                            Text(section.1).kjSmall(faint: true)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Button(action: done) {
                    Text("Start").kjKicker()
                }
                .buttonStyle(HouseButtonStyle(solid: true))
                .focused($startFocused)
                .accessibilityIdentifier("welcomeStart")
            }
            .frame(width: 720, alignment: .leading)
            .padding(.leading, KJLayout.inset)
            .padding(.vertical, 60)

            Spacer(minLength: 40)

            PlayerLayerView(player: reel.player)
                .frame(width: Self.pictureSize.width, height: Self.pictureSize.height)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.ground.ignoresSafeArea())
        // The page lays out its own margins: the text at the house inset, the picture to the edge.
        .ignoresSafeArea()
        .foregroundStyle(palette.ink)
        .defaultFocus($startFocused, true)
        .onExitCommand(perform: done)
        .onAppear { reel.start(skin: model.skin, moving: !reduceMotion) }
        // Automatic can turn the skin while the page is up (dawn, dusk): the clips follow it.
        .onChange(of: model.skin) { _, skin in reel.stop(); reel.start(skin: skin, moving: !reduceMotion) }
        .onDisappear { reel.stop() }
    }

    /// The sections this build carries, Account aside, each with one plain line.
    private var sections: [(Section, String)] {
        Section.available.compactMap { section in
            switch section {
            case .receiver:
                let live = model.receiver.index?.totals.live
                return (section, "Live channels, found by region on the map." + (live.map { " \($0.formatted()) on air now." } ?? ""))
            case .transmission: return (section, "Khajistan's own channels, on a schedule.")
            case .rooms: return (section, StoreBuild.roomsAreScreeningOnly ? "Films from the archive." : "Films, the Bazaar, the Madrassa and the databases.")
            case .reading: return (section, "Magazines and books from the archive, page by page.")
            case .picsvids: return (section, "Photographs and videos from the region's internet.")
            case .chat: return (section, "Talk with other viewers.")
            case .account: return nil
            }
        }
    }
}

/// The ident once, then the wordmark on a loop. Under Reduce Motion the wordmark stands still.
@MainActor
final class WelcomeReel {
    let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var observer: NSObjectProtocol?

    private var skin = Skin.day

    private func item(_ name: String) -> AVPlayerItem? {
        Bundle.main.url(forResource: "welcome-\(name)-\(skin.rawValue)", withExtension: "mp4").map { AVPlayerItem(url: $0) }
    }

    func start(skin: Skin, moving: Bool) {
        self.skin = skin
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        guard moving else {
            if let still = item("wordmark") {
                player.replaceCurrentItem(with: still)
                player.seek(to: CMTime(seconds: 4, preferredTimescale: 600))
            }
            return
        }
        guard let ident = item("ident") else { loop(); return }
        player.replaceCurrentItem(with: ident)
        observer = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: ident, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.loop() }
        }
        player.play()
    }

    private func loop() {
        guard let wordmark = item("wordmark") else { return }
        player.removeAllItems()
        looper = AVPlayerLooper(player: player, templateItem: wordmark)
        player.play()
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        looper?.disableLooping()
        looper = nil
        player.pause()
        player.removeAllItems()
    }
}

/// Whether the welcome is due: once per device, in Release builds; a Debug build shows it only
/// with `-kjwelcome YES`, so the UI tests never meet it.
enum Welcome {
    static let key = "kj.welcomed.v1"

    static var due: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "kjwelcome")
        #else
        return !UserDefaults.standard.bool(forKey: key)
        #endif
    }
}
