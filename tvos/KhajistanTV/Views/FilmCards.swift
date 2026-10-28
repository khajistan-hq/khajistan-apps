import SwiftUI

/// The films on a shelf. Select opens a film on its preview, as the Receiver's shelves do, or,
/// in the Screening Room, on its page (`opensPage`), as the Apple TV app does.
struct FilmShelf: View {
    let title: String
    let count: String
    let films: [Film]
    var onChoose: () -> Void = {}
    var opensPage = false
    /// Up Next: each card says where this device stopped the full film.
    var showsPlaces = false
    @State private var playing: Film?

    var body: some View {
        Shelf(title, count: count) {
            ForEach(films) { film in
                Button {
                    onChoose()
                    playing = film
                } label: {
                    FilmCard(film: film, place: showsPlaces ? FilmPlaces.position(film.handle) : nil)
                }
                .buttonStyle(HouseCardStyle())
                .accessibilityIdentifier(showsPlaces ? "upnext-\(film.handle)" : "film-\(film.handle)")
                .accessibilityLabel([Films.displayTitle(film), Films.offer(film)].compactMap { $0 }.joined(separator: ", "))
            }
        }
        .fullScreenCover(item: $playing) { film in
            if opensPage { TVFilmPage(film: film) } else { FilmPlayerView(film: film) }
        }
    }
}

/// A film's card: the poster whole at its own shape, over the title, the offer line and what the
/// record says. The poster has a fixed height, so a shelf is the same height from its first card
/// to its last; its width is the poster's own ratio. The title, the offer and the detail have a
/// fixed box too, so the cards line up whatever the record carries.
struct FilmCard: View {
    static let posterHeight: CGFloat = 420
    static let textHeight: CGFloat = 210

    let film: Film
    /// Seconds in, where this device stopped the full film: a progress line and the time take the
    /// offer line's place.
    var place: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FilmPoster(film: film, height: Self.posterHeight, maxPixel: 900)
                // How far in, on the artwork, as the Apple TV app draws Up Next.
                .overlay(alignment: .bottom) {
                    if let place, let minutes = film.runtime_minutes, minutes > 0 {
                        TVProgressLine(value: place / Double(minutes * 60)).padding(16)
                    }
                }
                .kjCardArt()
            // The text takes the poster's width, so a long title wraps under its own poster.
            Color.clear
                .frame(height: Self.textHeight)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Films.displayTitle(film))
                            .kjName(28)
                            .lineLimit(2)
                        if let place {
                            Kicker("Stopped at \(Mixes.clock(place))").lineLimit(1)
                        } else if let offer = Films.offer(film) {
                            Kicker(offer)
                                .lineLimit(3)
                        }
                        let detail = Films.detail(film)
                        if !detail.isEmpty {
                            Text(detail)
                                .kjSmall(faint: true)
                                .lineLimit(1)
                        }
                    }
                }
        }
    }
}

/// A poster fitted whole: never cropped, never letterboxed. Until it arrives a lift plate holds a
/// 2:3 space; once it has, the picture alone at its own ratio, faded in over the plate.
struct FilmPoster: View {
    let film: Film
    let height: CGFloat
    let maxPixel: Int
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var image: UIImage?

    private var ratio: CGFloat {
        if let image, image.size.height > 0 { return image.size.width / image.size.height }
        return 2.0 / 3.0
    }

    var body: some View {
        ZStack {
            // The plate and the picture cross-fade, so the ground never shows between them.
            Rectangle()
                .fill(palette.lift)
                .opacity(image == nil ? 1 : 0)
            FadeIn(shown: image != nil) {
                Image(uiImage: image ?? UIImage())
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .animation(.easeOut(duration: 0.35), value: image == nil)
        .frame(width: height * ratio, height: height)
        .task(id: film.handle) {
            let store = model.films
            guard let url = Films.posterURL(film, origin: store.origin) else { return }
            image = await PnvImages.shared.image([url], maxPixel: maxPixel, authorization: store.authorization)
        }
        .accessibilityHidden(true)
    }
}
