import Combine
import SwiftUI

/// Where a full film stopped, on this device: seconds in, by film handle. Never a stream address,
/// which expires and carries access; whether the viewer may still watch is asked again on Play.
enum FilmPlaces {
    private static let key = "kj.filmPlaces"
    /// Under half a minute in, or within two minutes of the end, there is nothing to resume.
    private static let least: Double = 30
    private static let tail: Double = 120

    static func position(_ handle: String) -> Double? {
        (UserDefaults.standard.dictionary(forKey: key)?[handle] as? Double).flatMap { $0 > least ? $0 : nil }
    }

    static func record(_ handle: String, at seconds: Double, of duration: Double?) {
        guard seconds > least, duration.map({ seconds < $0 - tail }) ?? true else { return forget(handle) }
        var all = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        all[handle] = seconds
        UserDefaults.standard.set(all, forKey: key)
    }

    /// Every place, for a screen that redraws when one changes.
    static var all: [String: Double] {
        (UserDefaults.standard.dictionary(forKey: key) ?? [:]).compactMapValues { $0 as? Double }
    }

    static func forget(_ handle: String) {
        var all = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        all[handle] = nil
        UserDefaults.standard.set(all, forKey: key)
    }

    /// The catalogue's films stopped part-way on this device.
    static func stopped(_ films: [Film]) -> [Film] {
        films.filter { position($0.handle) != nil }
    }
}

/// The Screening Room as the Apple TV app lays it: Up Next from this device, the account's
/// watchlist, then a poster shelf for each country the catalogue names. A poster opens the film's
/// page; the page holds the one Play.
struct TVScreeningRoom: View {
    @Environment(AppModel.self) private var model
    /// The places as last drawn: a film stopped or finished in the player redraws Up Next.
    @State private var places = FilmPlaces.all

    var body: some View {
        TVPage("Screening Room", line: model.films.state == .ready
               ? "\(model.films.films.count.formatted()) films Khajistan holds and distributes" : nil) {
            switch model.films.state {
            case .idle, .loading: TuningLoader("Loading\u{2026}").frame(maxWidth: .infinity)
            case .locked: Text("The Screening Room's catalogue is behind the site password while the archive is in preview. Set it under Account.").kjBody()
            case .failed(let message): Text(message).kjBody()
            case .ready: shelves
            }
        }
        .task(id: model.auth.previewPassword) { await model.films.load() }
        .task(id: model.auth.email) { await model.saves.load() }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).receive(on: RunLoop.main)) { _ in
            let now = FilmPlaces.all
            if now != places { places = now }
        }
    }

    @ViewBuilder
    private var shelves: some View {
        let films = model.films.films
        let stopped = films.filter { places[$0.handle] != nil && FilmPlaces.position($0.handle) != nil }
        if !stopped.isEmpty {
            FilmShelf(title: "Up Next", count: stopped.count.formatted(), films: stopped, opensPage: true, showsPlaces: true)
        }
        let listed = model.saves.watchlist.compactMap { handle in films.first { $0.handle == handle } }
        if model.auth.isSignedIn && !listed.isEmpty {
            FilmShelf(title: "Your watchlist", count: listed.count.formatted(), films: listed, opensPage: true)
        }
        let byCountry = Dictionary(grouping: films) { ($0.country ?? "").trimmingCharacters(in: .whitespaces) }
        let countries = byCountry.keys.filter { !$0.isEmpty }.sorted { (byCountry[$0]!.count, $1) > (byCountry[$1]!.count, $0) }
        ForEach(countries, id: \.self) { country in
            FilmShelf(title: country, count: byCountry[country]!.count.formatted(), films: byCountry[country]!, opensPage: true)
        }
        if let unfiled = byCountry[""] {
            FilmShelf(title: "Other films", count: unfiled.count.formatted(), films: unfiled, opensPage: true)
        }
    }
}

/// A film's page, as the Apple TV app's: the poster whole at left; the title, its line, one Play
/// (Resume where this device stopped the full film), the preview and the watchlist beside it,
/// then what the record says. Play asks vod-token in the player, which answers in the site's words.
struct TVFilmPage: View {
    let film: Film
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var playing: Mode?
    @State private var showSignIn = false
    @State private var watchNote: String?
    @State private var showWebsite = false
    @FocusState private var playFocused: Bool

    private enum Mode: String, Identifiable {
        case full, preview
        var id: String { rawValue }
    }

    var body: some View {
        // Read on every draw, so a film stopped in the player shows Resume on the way back.
        let place = playing == nil ? FilmPlaces.position(film.handle) : nil
        ZStack {
            palette.ground.ignoresSafeArea()
            HStack(alignment: .top, spacing: 80) {
                FilmPoster(film: film, height: 720, maxPixel: 1400)
                VStack(alignment: .leading, spacing: 18) {
                    Kicker("Screening Room")
                    Text(Films.displayTitle(film))
                        .kjDisplay(KJType.headline, tracking: -0.055)
                        .accessibilityAddTraits(.isHeader)
                    let line = [film.year.map(String.init), film.runtime_minutes.map(Self.runtime), film.country]
                        .compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        .joined(separator: " \u{00B7} ")
                    if !line.isEmpty { Text(line).kjBody() }
                    actions(place: place)
                        .padding(.vertical, 12)
                    if let place, let minutes = film.runtime_minutes, minutes > 0 {
                        TVProgressLine(value: place / Double(minutes * 60)).frame(width: 420)
                    }
                    if let watchNote { Text(watchNote).kjSmall(faint: true) }
                    if PassportSaves.filmRef(film.handle) == nil {
                        Text("This film cannot be kept on a watchlist yet.").kjSmall(faint: true)
                    }
                    information
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(KJLayout.inset)
        }
        .foregroundStyle(palette.ink)
        .defaultFocus($playFocused, true)
        .onAppear { OpenedLately.record(.film, ref: film.handle, title: Films.displayTitle(film)) }
        .task { await model.saves.load() }
        .fullScreenCover(item: $playing) { mode in
            FilmPlayerView(film: film, startsFull: mode == .full)
        }
        .fullScreenCover(isPresented: $showSignIn) {
            SignInView(onSignedIn: {}).environment(\.palette, palette)
        }
        // In place over the page, not one more cover: a third cover deep kept re-laying itself
        // out in Day under accessibility and stopped answering the remote.
        .disabled(showWebsite)
        .accessibilityHidden(showWebsite)
        .overlay {
            if showWebsite {
                TVOnYourPhone(title: Films.displayTitle(film), url: Films.pageURL(film)) { showWebsite = false }
            }
        }
    }

    private func actions(place: Double?) -> some View {
        HStack(spacing: 24) {
            Button { playing = .full } label: {
                Label(place.map { "Resume from \(Mixes.clock($0))" } ?? "Play", systemImage: "play.fill").kjKicker()
            }
            .buttonStyle(HouseButtonStyle(solid: true))
            .focused($playFocused)
            .accessibilityIdentifier("filmPlay")
            if Films.previewURL(film) != nil {
                Button { playing = .preview } label: { Label("Preview", systemImage: "play.rectangle").kjKicker() }
                    .buttonStyle(HouseButtonStyle())
                    .accessibilityIdentifier("filmPreview")
            }
            let listed = model.saves.isSaved(film: film.handle)
            Button { toggleWatchlist() } label: {
                Label(listed ? "On your watchlist" : "Watchlist", systemImage: listed ? "checkmark" : "plus").kjKicker()
            }
            .buttonStyle(HouseButtonStyle())
            .disabled(PassportSaves.filmRef(film.handle) == nil)
            .accessibilityIdentifier("filmWatchlist")
            .accessibilityValue(listed ? "On" : "Off")
            // The TV has no browser: the film's page opens on the phone, from a code.
            Button { showWebsite = true } label: { Label("Website", systemImage: "safari").kjKicker() }
                .buttonStyle(HouseButtonStyle())
                .accessibilityIdentifier("filmOnWebsite")
        }
        .focusSection()
    }

    /// What the record says, label beside value, as the Apple TV app's Information section.
    private var information: some View {
        let rows: [(String, String?)] = [
            ("Publisher", film.publisher), ("Country", film.country), ("Year", film.year.map(String.init)),
            ("Running time", film.runtime_minutes.map(Self.runtime)), ("Languages", film.languages?.text),
            ("Licensing", film.licence_price != nil ? "Institutional licence, by inquiry on the film's page" : nil),
        ]
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(rows.filter { !($0.1 ?? "").trimmingCharacters(in: .whitespaces).isEmpty }, id: \.0) { label, value in
                HStack(alignment: .firstTextBaseline, spacing: 24) {
                    Text(label).kjKicker(palette.faint).frame(width: 260, alignment: .leading)
                    Text(value ?? "").kjBody().lineLimit(2)
                }
                .accessibilityElement(children: .combine)
            }
            let page = Films.pageURL(film)
            Text("On the website: " + (page.host ?? "") + page.path).kjSmall(faint: true).lineLimit(1)
            Text(Films.attribution).kjSmall(faint: true)
        }
        .padding(.top, 8)
    }

    private func toggleWatchlist() {
        guard model.saves.canSave else { showSignIn = true; return }
        Task {
            await model.saves.load()
            watchNote = await model.saves.toggle(film: film.handle, title: Films.displayTitle(film)) ? nil : "That did not save. Try again."
        }
    }

    static func runtime(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }
}

/// A page of the website, opened on the phone: a QR for it and its address, as the sign-in screen
/// offers its own. The TV has no browser, so this is what Website does here. Drawn in place over
/// the screen that asked for it; Menu or Select closes it.
struct TVOnYourPhone: View {
    let title: String
    let url: URL
    var line = "Point your phone's camera at the code to open this page."
    let close: () -> Void
    @FocusState private var backFocused: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        // Dark modules on a light plate in every skin, as on the sign-in screen: phone cameras
        // read an inverted QR badly.
        let day = model.skin == .day
        let dark = day ? palette.ink : palette.ground
        let light = day ? palette.ground : palette.ink
        ZStack {
            palette.ground.ignoresSafeArea()
            HStack(alignment: .center, spacing: 80) {
                ZStack {
                    light
                    if let grid = QRModules.grid(url.absoluteString) {
                        QRModulesView(grid: grid, colour: dark).padding(36)
                            .accessibilityLabel("QR code for the page on the website")
                            .accessibilityIdentifier("websiteQR")
                    }
                }
                .frame(width: 520, height: 520)
                VStack(alignment: .leading, spacing: 18) {
                    Kicker("On the website")
                    Text(title).kjDisplay(KJType.headline, tracking: -0.055).lineLimit(3)
                    Text(line).kjBody()
                    Text((url.host ?? "") + url.path).kjName(30).lineLimit(2).minimumScaleFactor(0.6)
                        .accessibilityIdentifier("websiteAddress")
                    Button(action: close) { Text("Back").kjKicker() }
                        .buttonStyle(HouseButtonStyle())
                        .focused($backFocused)
                        .padding(.top, 12)
                        .accessibilityIdentifier("websiteBack")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(KJLayout.inset)
        }
        .foregroundStyle(palette.ink)
        .defaultFocus($backFocused, true)
        .onAppear { backFocused = true }
        .onExitCommand(perform: close)
        .accessibilityAddTraits(.isModal)
    }
}

/// How far in, as the Apple TV app draws it under Up Next: the lift as the track, ink as the part
/// watched. No outline.
struct TVProgressLine: View {
    let value: Double
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { box in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.lift)
                Capsule().fill(palette.ink).frame(width: box.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel("Watched")
        .accessibilityValue("\(Int((min(max(value, 0), 1) * 100).rounded())) percent")
    }
}
