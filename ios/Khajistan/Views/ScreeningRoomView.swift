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
                LargeTitle(title: "Screening Room",
                           line: store.state == .ready ? "\(store.films.count.formatted()) films Khajistan holds and distributes" : nil)
                switch store.state {
                case .idle, .loading:
                    TuningLoader("Loading the Screening Room\u{2026}").frame(maxWidth: .infinity).padding(.top, 40)
                case .locked:
                    LockedNote(subject: "The Screening Room's catalogue")
                case .failed(let message):
                    ReadingProblem(message: message) { Task { await store.load() } }
                case .ready:
                    SearchField(prompt: "Title, country, language", text: $query, id: "filmSearch")
                    if countries.count > 1 {
                        ChipRow(chips: [Chip(id: "", title: "All", identifier: "filmCountry-all")]
                                    + countries.map { Chip(id: $0, title: $0, identifier: "filmCountry-\($0)") },
                                selected: country ?? "") { country = $0.isEmpty ? nil : $0 }
                    }
                    if trimmed.isEmpty && country == nil {
                        upNextRow
                        watchlistRow
                        ForEach(countries, id: \.self) { name in
                            row(name, films: store.films.filter { $0.country?.trimmingCharacters(in: .whitespaces) == name })
                        }
                        let unfiled = store.films.filter { ($0.country ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
                        if !unfiled.isEmpty { row("Other films", films: unfiled, opens: false) }
                    } else {
                        Text("\(shown.count.formatted()) of \(store.films.count.formatted()) films")
                            .kjSmall(faint: true)
                            .accessibilityIdentifier("filmCount")
                        grid
                    }
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

    private var posterWidth: CGFloat { sizeClass == .regular ? 160 : 128 }

    /// A shelf of posters, as the Apple TV app sets a row; its heading opens the whole shelf.
    private func row(_ name: String, films: [Film], opens: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ShelfHeader(title: name, count: films.count, action: opens ? { country = name } : nil)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(films) { FilmCard(film: $0, width: posterWidth) }
                }
            }
            .scrollClipDisabled()
        }
    }

    /// Up Next: the full films stopped on this device, with how far in, as the Apple TV app's row.
    @ViewBuilder
    private var upNextRow: some View {
        let stopped: [(Film, Resume)] = model.library.resume.filter { $0.kind == .film && $0.position > 30 }.compactMap { place in
            store.films.first { $0.handle == place.ref }.map { ($0, place) }
        }
        if !stopped.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ShelfHeader(title: "Up Next")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(stopped, id: \.0.id) { film, place in
                            FilmCard(film: film, width: posterWidth * 1.15,
                                     progress: film.runtime_minutes.flatMap { $0 > 0 ? place.position / Double($0 * 60) : nil },
                                     line: "Stopped at \(FilmPlayback.clock(place.position))")
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    /// The account's watchlist, as films still in the catalogue, when there is one.
    @ViewBuilder
    private var watchlistRow: some View {
        let listed = model.saves.watchlist.compactMap { handle in store.films.first { $0.handle == handle } }
        if model.auth.isSignedIn && !listed.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ShelfHeader(title: "Your watchlist", count: listed.count)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(listed) { film in
                            FilmCard(film: film, width: posterWidth).accessibilityIdentifier("watchlist-\(film.handle)")
                        }
                    }
                }
                .scrollClipDisabled()
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

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: sizeClass == .regular ? 160 : 104), spacing: 14, alignment: .top)],
                  alignment: .leading, spacing: 22) {
            ForEach(shown) { FilmCard(film: $0, width: nil) }
        }
    }
}

/// A film on a shelf: the poster at its own shape, then the title and a faint line.
struct FilmCard: View {
    let film: Film
    @Environment(AppModel.self) private var model
    let width: CGFloat?
    var progress: Double?
    var line: String?
    /// True on Home, which is not on the room's stack.
    var fromHome = false

    var body: some View {
        RoomLink(route: .film(film.handle), in: fromHome ? .screening : nil) {
            VStack(alignment: .leading, spacing: 6) {
                FilmPoster(film: film)
                if let progress { ProgressLine(value: progress) }
                Text(Films.displayTitle(film)).font(.system(.subheadline, weight: .semibold)).lineLimit(2)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                if let text = line ?? film.country { Text(text).kjSmall(faint: true).lineLimit(1) }
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("film-\(film.handle)")
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

    /// The poster at its own shape, standing on the row's line; the plate holds the space until then.
    var body: some View {
        Color.clear
            .aspectRatio(0.68, contentMode: .fit)
            .overlay(alignment: .bottom) {
                if let image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(palette.lift)
                }
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

    /// The Apple TV app's film page: the poster, the title and its line, one Play, the smaller
    /// actions under it, then the information the record carries.
    @ViewBuilder
    private func content(_ film: Film) -> some View {
        VStack(spacing: 14) {
            FilmPoster(film: film).frame(maxWidth: sizeClass == .regular ? 300 : 230)
            VStack(spacing: 4) {
                Text(Films.displayTitle(film)).font(.system(.title2, weight: .bold)).multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                let line = [film.year.map(String.init), film.runtime_minutes.map(Self.runtime), film.country]
                    .compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
                if !line.isEmpty { Text(line).kjSmall(faint: true).multilineTextAlignment(.center) }
                if let languages = film.languages?.text, !languages.isEmpty {
                    Text(languages).kjSmall(faint: true).multilineTextAlignment(.center)
                }
            }
            actions(film)
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        information(film)
    }

    static func runtime(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }

    @ViewBuilder
    private func actions(_ film: Film) -> some View {
        let place = model.library.place(.film, film.handle).flatMap { $0.position > 30 ? $0 : nil }
        VStack(spacing: 12) {
            Button { Task { await watchFull(film) } } label: {
                Label(checking ? "Asking\u{2026}" : (place.map { "Resume from \(FilmPlayback.clock($0.position))" } ?? "Play"),
                      systemImage: "play.fill")
            }
            .buttonStyle(SolidActionStyle())
            .disabled(checking)
            .accessibilityIdentifier("filmWatchFull")
            if let place, let minutes = film.runtime_minutes, minutes > 0 {
                ProgressLine(value: place.position / Double(minutes * 60))
            }
            if let refusal {
                Text(Self.refusalText(film, status: refusal)).kjBody().multilineTextAlignment(.center)
                    .accessibilityIdentifier("filmRefusal")
                if refusal == 401 {
                    Button(kicker: "Sign in") { showSignIn = true }.accessibilityIdentifier("filmSignIn")
                }
            }
            HStack(spacing: 8) {
                watchlistButton(film)
                if let url = Films.previewURL(film) {
                    IconAction(title: "Preview", symbol: "play.rectangle") {
                        model.tuner.stop()
                        playing = FilmPlayback(film: film, url: url, isFull: false, line: "Preview", startAt: 0)
                    }
                    .accessibilityIdentifier("filmPreview")
                }
                IconAction(title: "Website", symbol: "safari") { model.open(Films.pageURL(film)) }
                    .accessibilityIdentifier("filmOnWebsite")
            }
            if PassportSaves.filmRef(film.handle) == nil {
                Text("This film cannot be kept on a watchlist yet.").kjSmall(faint: true).multilineTextAlignment(.center)
            }
            if let watchNote { Text(watchNote).kjSmall(faint: true) }
        }
    }

    /// What the record says, label over value, as the Apple TV app's Information section.
    @ViewBuilder
    private func information(_ film: Film) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ShelfHeader(title: "Information")
            if let publisher = film.publisher, !publisher.isEmpty { InfoRow(label: "Publisher", value: publisher) }
            if let country = film.country, !country.isEmpty { InfoRow(label: "Country", value: country) }
            if let year = film.year { InfoRow(label: "Year", value: String(year)) }
            if let minutes = film.runtime_minutes { InfoRow(label: "Running time", value: Self.runtime(minutes)) }
            if let languages = film.languages?.text, !languages.isEmpty { InfoRow(label: "Languages", value: languages) }
            if film.licence_price != nil {
                InfoRow(label: "Licensing", value: "Institutional licence, by inquiry on the film's page")
            }
            Text(Films.attribution).kjSmall(faint: true)
        }
        .padding(.top, 8)
    }

    /// The watchlist is on the account, with the other saves the website's profile page lists.
    private func watchlistButton(_ film: Film) -> some View {
        let listed = model.saves.isSaved(film: film.handle)
        // The account's saves take Latin-script ids only; a film filed under another script
        // cannot be kept there, and the page says so rather than the button doing nothing.
        return IconAction(title: "Watchlist", symbol: listed ? "checkmark" : "plus") {
            guard model.saves.canSave else { showSignIn = true; return }
            Task {
                await model.saves.load()
                watchNote = await model.saves.toggle(film: film.handle, title: Films.displayTitle(film)) ? nil : "That did not save. Try again."
            }
        }
        .disabled(PassportSaves.filmRef(film.handle) == nil)
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
