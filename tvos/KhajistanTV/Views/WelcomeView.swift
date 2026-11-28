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
    /// Made once, on appear: a @State initial value is built again on every init of the view.
    @State private var reel: WelcomeReel?
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

            Group {
                if let reel { PlayerLayerView(player: reel.player) } else { Color.clear }
            }
            .frame(width: Self.pictureSize.width, height: Self.pictureSize.height)
            #if DEBUG
            // Read by WelcomeUITests past the ident and one turn of the wordmark.
            .overlay { TimelineView(.periodic(from: .now, by: 1)) { _ in
                Color.clear.accessibilityElement()
                    .accessibilityIdentifier("welcomePicture")
                    .accessibilityValue(reel?.probe ?? "stopped")
            } }
            #else
            .accessibilityHidden(true)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.ground.ignoresSafeArea())
        // The page lays out its own margins: the text at the house inset, the picture to the edge.
        .ignoresSafeArea()
        .foregroundStyle(palette.ink)
        .defaultFocus($startFocused, true)
        .onExitCommand(perform: done)
        .onAppear {
            model.welcomeAppeared = true
            let reel = reel ?? WelcomeReel()
            self.reel = reel
            reel.start(skin: model.skin, moving: !reduceMotion)
        }
        // Automatic can turn the skin while the page is up (dawn, dusk), and Reduce Motion can be
        // turned on: the clips follow either.
        .onChange(of: model.skin) { _, skin in reel?.start(skin: skin, moving: !reduceMotion) }
        .onChange(of: reduceMotion) { _, still in reel?.start(skin: model.skin, moving: !still) }
        .onDisappear { reel?.stop() }
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

/// The ident once, then the wordmark on a loop, from one queue: the wordmark is queued behind the
/// ident, so the handover has no blank beat, and an ident that fails or stalls is skipped. Under
/// Reduce Motion the wordmark stands still. Every callback checks it belongs to the run that is on,
/// so a skin change or a dismiss in between never starts a stopped reel.
@MainActor
final class WelcomeReel {
    let player = AVQueuePlayer()
    private var observers: [NSObjectProtocol] = []
    private var itemWatch: NSKeyValueObservation?
    private var run = 0
    private var skin = Skin.day

    private func item(_ name: String) -> AVPlayerItem? {
        Bundle.main.url(forResource: "welcome-\(name)-\(skin.rawValue)", withExtension: "mp4").map { AVPlayerItem(url: $0) }
    }

    func start(skin: Skin, moving: Bool) {
        stop()
        run += 1
        let current = run
        self.skin = skin
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        guard let wordmark = item("wordmark") else { return }
        // The queue drops an item that ends while this is `.advance`, so the wordmark, the last
        // item, must end on `.none`, or the page goes blank 18 s in (round-2 review, measured).
        player.actionAtItemEnd = .none
        guard moving else {
            player.insert(wordmark, after: nil)
            player.seek(to: CMTime(seconds: 4, preferredTimescale: 600))
            return
        }
        let ident = item("ident")
        if let ident {
            player.insert(ident, after: nil)
            player.actionAtItemEnd = .advance
        }
        player.insert(wordmark, after: ident)
        let center = NotificationCenter.default
        // Once the queue is on the wordmark, an end holds rather than dropping it. Watched on the
        // current item, not on the ident's end, which can arrive before the queue has moved.
        itemWatch = player.observe(\.currentItem, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.run == current, player.currentItem === wordmark else { return }
                    self.player.actionAtItemEnd = .none
                }
            }
        }
        // The wordmark again from its start when it ends: the loop.
        observers.append(center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: wordmark, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.run == current else { return }
                self.player.seek(to: .zero)
                self.player.play()
            }
        })
        // An ident that cannot play hands over at once.
        if let ident {
            for name in [AVPlayerItem.failedToPlayToEndTimeNotification, AVPlayerItem.playbackStalledNotification] {
                observers.append(center.addObserver(forName: name, object: ident, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, self.run == current, self.player.currentItem === ident else { return }
                        self.player.actionAtItemEnd = .none
                        self.player.advanceToNextItem()
                        self.player.play()
                    }
                })
            }
        }
        player.play()
    }

    /// What is on the picture and where: "ident 4.1", "wordmark 0.8", or "stopped". The UI test reads
    /// it over 30 s to see the wordmark go back to its start, which a frozen last frame never does.
    var probe: String {
        guard let item = player.currentItem, player.rate > 0 else { return "stopped" }
        let name = (item.asset as? AVURLAsset)?.url.lastPathComponent.contains("ident") == true ? "ident" : "wordmark"
        return String(format: "%@ %.1f", name, player.currentTime().seconds)
    }

    func stop() {
        run += 1
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        itemWatch?.invalidate()
        itemWatch = nil
        player.pause()
        player.removeAllItems()
    }
}

/// Whether the welcome is due: once per device, in Release builds. A Debug build shows it only
/// when asked, so no other UI test meets it: `-kjwelcome YES` always, `-kjwelcome once` as Release
/// does (with `-kjwelcomereset YES` forgetting it was seen), for the test that it comes only once.
enum Welcome {
    static let key = "kj.welcomed.v1"

    static var due: Bool {
        #if DEBUG
        let defaults = UserDefaults.standard
        switch defaults.string(forKey: "kjwelcome") {
        case "YES": return true
        case "once":
            if defaults.bool(forKey: "kjwelcomereset") { defaults.removeObject(forKey: key) }
            return !defaults.bool(forKey: key)
        default: return false
        }
        #else
        return !UserDefaults.standard.bool(forKey: key)
        #endif
    }
}
