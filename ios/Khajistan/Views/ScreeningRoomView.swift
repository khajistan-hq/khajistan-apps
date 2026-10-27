import AVKit
import SwiftUI

/// The Screening Room: the films of data/khajistan-tv/vod.json (Core/Films.swift, as the Apple TV
/// app reads it). Each film opens on its own page with what its record says, its public preview,
/// and the full film for a viewer the server lets watch it. Sales are paused (owner, 2026-10-05):
/// nothing here sells, and a refusal never says "rent it here". Licensing is the film's own page
/// on the website.
struct ScreeningRoomView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var query = ""
    @State private var country: String?

    private var store: FilmStore { model.films }
    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                PageHead("Screening Room", line: "Films Khajistan holds and distributes, and institutional licensing.")
                switch store.state {
                case .idle, .loading:
                    TuningLoader("Loading the Screening Room\u{2026}").frame(maxWidth: .infinity).padding(.top, 40)
                case .locked:
                    LockedNote(subject: "The Screening Room's catalogue")
                case .failed(let message):
                    ReadingProblem(message: message) { Task { await store.load() } }
                case .ready:
                    watchlistRow
                    filters
                    grid
                }
            }
            .padding(.horizontal, KJLayout.inset)
            .padding(.vertical, 16)
            .frame(maxWidth: KJLayout.wideWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        // Loaded again when the preview password changes: the catalogue is behind it until launch.
        .task(id: model.auth.previewPassword) { await store.load() }
        .task(id: model.auth.email) { await model.saves.load() }
    }

    /// The account's watchlist, as films still in the catalogue, when there is one.
    @ViewBuilder
    private var watchlistRow: some View {
        let listed = model.saves.watchlist.compactMap { handle in store.films.first { $0.handle == handle } }
        if model.auth.isSignedIn && !listed.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Kicker("Your watchlist").accessibilityAddTraits(.isHeader)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(listed) { film in
                            NavigationLink(value: RoomRoute.film(film.handle)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    FilmPoster(film: film).frame(width: 110)
                                    Text(Films.displayTitle(film)).kjSmall().lineLimit(2).frame(width: 110, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("watchlist-\(film.handle)")
                        }
                    }
                }
            }
            .task { await model.saves.load() }
        }
    }

    /// The countries the catalogue itself names, in order of how many films each holds.
    private var countries: [String] {
        let counts = Dictionary(grouping: store.films.compactMap { $0.country?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }, by: { $0 })
        return counts.keys.sorted { (counts[$0]!.count, $1) > (counts[$1]!.count, $0) }
    }

    private var shown: [Film] {
        let needle = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return store.films.filter { film in
            (country == nil || film.country?.trimmingCharacters(in: .whitespaces) == country)
                && (needle.isEmpty || [film.title, film.publisher, film.country, film.languages?.text].compactMap { $0 }
                    .contains { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains(needle) })
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            HouseInputField("Find a film") {
                TextField("", text: $query, prompt: Text("Title, country, language").foregroundStyle(palette.faint))
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("filmSearch")
            }
            if countries.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        chip("All", value: nil)
                        ForEach(countries, id: \.self) { chip($0, value: $0) }
                    }
                }
                .padding(.horizontal, -12)
            }
            Text("\(shown.count.formatted()) of \(store.films.count.formatted()) films")
                .kjSmall(faint: true)
                .accessibilityIdentifier("filmCount")
        }
    }

    private func chip(_ title: String, value: String?) -> some View {
        Button { country = value } label: { Text(title).kjKicker() }
            .buttonStyle(HouseTabStyle(isCurrent: country == value))
            .accessibilityIdentifier("filmCountry-\(value ?? "all")")
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: sizeClass == .regular ? 170 : 140), spacing: 16, alignment: .top)],
                  alignment: .leading, spacing: 22) {
            ForEach(shown) { film in
                NavigationLink(value: RoomRoute.film(film.handle)) {
                    VStack(alignment: .leading, spacing: 6) {
                        FilmPoster(film: film)
                        Text(Films.displayTitle(film)).kjName().lineLimit(3).multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if let country = film.country { Text(country).kjSmall(faint: true) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("film-\(film.handle)")
            }
        }
    }
}

/// A note for a room whose data is behind the site password while the archive is in preview.
struct LockedNote: View {
    let subject: String
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(subject) is behind the site password while the archive is in preview.").kjBody()
            Button(kicker: "Set it under Library \u{2192}") { model.tab = .library }
                .accessibilityIdentifier("lockedToLibrary")
        }
        // A container, so the button inside stays its own element for VoiceOver.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("roomLocked")
    }
}

/// A film's poster at its own shape on the lift colour, never cropped.
private struct FilmPoster: View {
    let film: Film
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(palette.lift)
            .aspectRatio(0.68, contentMode: .fit)
            .overlay {
                if let image { Image(uiImage: image).resizable().aspectRatio(contentMode: .fit) }
            }
            .accessibilityHidden(true)
            .task(id: film.handle) {
                guard let url = Films.posterURL(film, origin: model.films.origin) else { return }
                image = await PnvImages.shared.image([url], maxPixel: 600, authorization: model.films.authorization)
            }
    }
}

// MARK: - One film

struct FilmScreen: View {
    let handle: String

    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var playing: FilmPlayback?
    @State private var checking = false
    @State private var refusal: Int?
    @State private var showSignIn = false
    @State private var watchNote: String?

    private var film: Film? { model.films.films.first { $0.handle == handle } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let film {
                    content(film)
                } else if model.films.state == .loading || model.films.state == .idle {
                    TuningLoader("Loading the Screening Room\u{2026}").frame(maxWidth: .infinity).padding(.top, 40)
                } else if model.films.state == .locked {
                    LockedNote(subject: "This film's record")
                } else {
                    Text("This film is not in the Screening Room now.").kjBody().accessibilityIdentifier("filmMissing")
                }
            }
            .padding(.horizontal, KJLayout.inset)
            .padding(.vertical, 12)
            .frame(maxWidth: KJLayout.wideWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task(id: model.auth.previewPassword) { await model.films.load() }
        .fullScreenCover(item: $playing) { playback in
            FilmPlayerScreen(playback: playback)
                .environment(model)
        }
        .sheet(isPresented: $showSignIn) { SignInView(onSignedIn: {}) }
    }

    @ViewBuilder
    private func content(_ film: Film) -> some View {
        let wide = sizeClass == .regular
        let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 28)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 18))
        layout {
            FilmPoster(film: film).frame(maxWidth: wide ? 300 : 220)
            VStack(alignment: .leading, spacing: 12) {
                Kicker("Screening Room")
                Text(Films.displayTitle(film)).kjDisplay(KJType.headline, tracking: -0.055).accessibilityAddTraits(.isHeader)
                let detail = Films.detail(film)
                if !detail.isEmpty { Text(detail).kjBody() }
                if let publisher = film.publisher, !publisher.isEmpty { Text(publisher).kjSmall(faint: true) }
                Text(Films.attribution).kjSmall(faint: true)
                if film.licence_price != nil {
                    Text("Institutional licence \u{00B7} by inquiry on the film's page").kjSmall()
                }
                actions(film)
            }
        }
    }

    @ViewBuilder
    private func actions(_ film: Film) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let place = model.library.place(.film, film.handle), place.position > 30 {
                Text("Stopped at \(FilmPlayback.clock(place.position)) on this device").kjSmall(faint: true)
                    .accessibilityIdentifier("filmStoppedAt")
            }
            HStack(spacing: 18) {
                watchlistButton(film)
                Button(kicker: checking ? "Asking\u{2026}" : "Watch the full film") { Task { await watchFull(film) } }
                    .disabled(checking)
                    .accessibilityIdentifier("filmWatchFull")
                if let url = Films.previewURL(film) {
                    Button(kicker: "Preview") {
                        model.tuner.stop()
                        playing = FilmPlayback(film: film, url: url, isFull: false, line: "Preview", startAt: 0)
                    }
                    .accessibilityIdentifier("filmPreview")
                }
            }
            if let refusal {
                Text(Self.refusalText(film, status: refusal)).kjBody().accessibilityIdentifier("filmRefusal")
                if refusal == 401 {
                    Button(kicker: "Sign in") { showSignIn = true }.accessibilityIdentifier("filmSignIn")
                }
            }
            Button(kicker: "The film's page on the website \u{2197}") { model.open(Films.pageURL(film)) }
                .accessibilityIdentifier("filmOnWebsite")
        }
        .padding(.top, 6)
    }

    /// The watchlist is on the account, with the other saves the website's profile page lists.
    @ViewBuilder
    private func watchlistButton(_ film: Film) -> some View {
        let listed = model.saves.isSaved(film: film.handle)
        // The account's saves take Latin-script ids only; a film filed under another script
        // cannot be kept there, and the control says so rather than doing nothing.
        let savable = PassportSaves.filmRef(film.handle) != nil
        VStack(alignment: .leading, spacing: 4) {
            Button(kicker: listed ? "On your watchlist" : "Add to watchlist") {
                guard model.saves.canSave else { showSignIn = true; return }
                Task {
                    await model.saves.load()
                    watchNote = await model.saves.toggle(film: film.handle, title: Films.displayTitle(film)) ? nil : "That did not save. Try again."
                }
            }
            .disabled(!savable)
            if !savable { Text("This film cannot be kept on a watchlist yet.").kjSmall(faint: true) }
            if let watchNote { Text(watchNote).kjSmall(faint: true) }
        }
        .accessibilityIdentifier("filmWatchlist")
        .accessibilityValue(listed ? "On" : "Off")
        .task { await model.saves.load() }
    }

    /// The site's denyText with sales paused: 401 is a sign-in, 403 is "not on your account" (or
    /// licensing for a licensed film), everything else is ours and says so.
    static func refusalText(_ film: Film, status: Int) -> String {
        switch status {
        case 401: return "Sign in to the Khajistan account that holds this film, then try again."
        case 403:
            return film.licence_price != nil
                ? "This film is licensed rather than sold. Screening and institutional terms are by inquiry on the film's page."
                : "This film is not on your Khajistan account."
        default: return Films.faultText
        }
    }

    private func watchFull(_ film: Film) async {
        checking = true
        refusal = nil
        let answer = await model.films.requestFullFilm(film)
        checking = false
        switch answer {
        case .granted(let token, let kind, let expiresAt):
            guard let url = Films.fullFilmURL(token: token) else { refusal = 0; return }
            model.tuner.stop()
            let resume = model.library.place(.film, film.handle)?.position ?? 0
            playing = FilmPlayback(film: film, url: url, isFull: true,
                                   line: Films.accessLine(kind: kind, expiresAt: expiresAt), startAt: resume)
        case .refused(let status):
            refusal = status
            if status == 401 { showSignIn = true }
        }
    }
}

/// What the player is given: the stream (a signed manifest for the full film, never kept), and
/// where to start. Only a full film's place is remembered.
struct FilmPlayback: Identifiable {
    let film: Film
    let url: URL
    let isFull: Bool
    let line: String
    let startAt: Double
    var id: String { film.handle + (isFull ? "|full" : "|preview") }

    static func clock(_ seconds: Double) -> String {
        let total = Int(seconds)
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// The system player over the app: its own scrubber, the manifest's subtitle tracks, picture in
/// picture and AirPlay. The picture sits on black (owner, 2026-10-05).
struct FilmPlayerScreen: View {
    let playback: FilmPlayback
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var player = AVPlayer()
    @State private var observer: Any?
    @State private var failed: String?
    @State private var watch: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            SystemPlayer(player: player).ignoresSafeArea()
            Button(kicker: "Close") { close() }
                .keyboardShortcut(.cancelAction)
                .padding(.horizontal, KJLayout.inset)
                .padding(.top, 8)
                .environment(\.palette, Palette(.grove))
                .accessibilityIdentifier("filmClose")
            if let failed {
                Text(failed).kjBody().foregroundStyle(Palette(.grove).ink).padding(KJLayout.inset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("filmFailed")
            }
        }
        .task { start() }
        .onDisappear { stop() }
    }

    private func start() {
        let asset = AVURLAsset(url: playback.url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": KJConfig.userAgent]])
        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        if playback.isFull, playback.startAt > 30 {
            player.seek(to: CMTime(seconds: playback.startAt, preferredTimescale: 600))
        }
        player.play()
        // Every ten seconds the full film's place is kept, by handle, on this device.
        if playback.isFull {
            observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 10, preferredTimescale: 1), queue: .main) { time in
                MainActor.assumeIsolated { remember(time.seconds) }
            }
        }
        watch = Task {
            for await status in item.publisher(for: \.status).values where status == .failed {
                failed = Films.faultText
            }
        }
    }

    private func remember(_ seconds: Double) {
        guard seconds.isFinite, seconds > 0 else { return }
        let total = player.currentItem?.duration.seconds ?? .nan
        // Near the end the film is finished: its place is cleared to the start.
        let place = total.isFinite && seconds > total - 60 ? 0 : seconds
        model.record(Resume(kind: .film, ref: playback.film.handle, part: nil, position: place,
                            title: Films.displayTitle(playback.film), detail: playback.line, date: .now))
    }

    private func stop() {
        watch?.cancel()
        watch = nil
        if let observer { player.removeTimeObserver(observer) }
        observer = nil
        if playback.isFull { remember(player.currentTime().seconds) }
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func close() {
        stop()
        dismiss()
    }
}

private struct SystemPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.view.backgroundColor = .black
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
}
