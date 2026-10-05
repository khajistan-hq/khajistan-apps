import Foundation
import TVServices

/// The Top Shelf: a carousel of the receiver and the two transmission channels, drawn from the
/// same public files the app reads. With nothing fetched, it returns nil and tvOS shows the
/// static banner from the asset catalog.
final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        Task {
            let items = await ShelfFeed.items()
            completionHandler(items.isEmpty ? nil : TVTopShelfCarouselContent(style: .actions, items: items))
        }
    }
}
