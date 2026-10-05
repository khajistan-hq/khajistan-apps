import SwiftUI

/// The Screening Room: every film in vod.json, in the catalogue's order, as the site's Film Vault
/// marquee carries them. A film is chosen, not tuned: Select opens it and plays its preview.
struct FilmsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        let films = model.films.films
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                VStack(alignment: .leading, spacing: 12) {
                    Kicker("Receiver \u{2192} The Screening Room")
                    Text("The Screening Room")
                        .kjDisplay()
                        .accessibilityAddTraits(.isHeader)
                    if !films.isEmpty {
                        Text("On Demand \u{00B7} \(films.count) \(films.count == 1 ? "film" : "films") in the Screening Room")
                            .kjBody()
                    }
                }
                if films.isEmpty {
                    TuningLoader("Loading\u{2026}")
                } else {
                    FilmGrid(films: films)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, KJLayout.inset)
            .padding(.vertical, 40)
        }
        .background(palette.ground.ignoresSafeArea())
        .foregroundStyle(palette.ink)
        .task { await model.films.load() }
    }
}

/// Films as poster cards, five across. Shared by the Screening Room and a region's On Demand.
struct FilmGrid: View {
    let films: [Film]
    @State private var playing: Film?

    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 28, alignment: .top), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 36) {
            ForEach(films) { film in
                Button {
                    playing = film
                } label: {
                    FilmCard(film: film)
                }
                .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)))
                .accessibilityIdentifier("film-\(film.handle)")
                .accessibilityLabel([Films.displayTitle(film), Films.offer(film)].compactMap { $0 }.joined(separator: ", "))
            }
        }
        // The cards' plate padding is pulled back so the posters sit on the page margin.
        .padding(.horizontal, -16)
        .fullScreenCover(item: $playing) { film in
            FilmPlayerView(film: film)
        }
    }
}

/// The poster at its own shape, the title, the offer line and what the record says.
struct FilmCard: View {
    let film: Film

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FilmPoster(film: film, maxPixel: 900)
            Text(Films.displayTitle(film))
                .kjName(28)
                .lineLimit(3)
            if let offer = Films.offer(film) {
                Kicker(offer)
                    .fixedSize(horizontal: false, vertical: true)
            }
            let detail = Films.detail(film)
            if !detail.isEmpty {
                Text(detail)
                    .kjSmall(faint: true)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// A poster fitted whole: never cropped, never letterboxed. Until it arrives a lift plate holds a
/// 2:3 space; once it has, the picture alone, at its own ratio.
struct FilmPoster: View {
    let film: Film
    let maxPixel: Int
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var image: UIImage?

    private var ratio: CGFloat {
        if let image, image.size.height > 0 { return image.size.width / image.size.height }
        return 2.0 / 3.0
    }

    var body: some View {
        Rectangle()
            .fill(image == nil ? palette.lift : Color.clear)
            .aspectRatio(ratio, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .task(id: film.handle) {
                let store = model.films
                guard let url = Films.posterURL(film, origin: store.origin) else { return }
                image = await PnvImages.shared.image([url], maxPixel: maxPixel, authorization: store.authorization)
            }
            .accessibilityHidden(true)
    }
}
