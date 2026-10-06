import SwiftUI

/// One shelf, as the TV app lays one: a title with its count, over a row of cards that scrolls
/// sideways. Cards are fixed in size and the stack is lazy, so a long shelf costs what is on
/// screen. The row runs under the page's side margin and past it, so a card scrolled out of the
/// column is still drawn up to the screen's edge, and a focused card's lift and shadow are never
/// clipped. A focus section, so a press up or down lands on the nearest card of the next shelf.
struct Shelf<Content: View>: View {
    let title: String
    let count: String?
    let content: Content

    init(_ title: String, count: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.count = count
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(title).kjName(38)
                if let count {
                    Text(count).kjSmall(faint: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 32) {
                    content
                }
                // Room under and over the cards for the lift (8%) and the shadow.
                .padding(.vertical, 40)
            }
            .scrollClipDisabled()
        }
        .focusSection()
    }
}

extension View {
    /// A page of shelves scrolled up under the top bar fades out there instead of ending in a
    /// sliver of card.
    func kjTopFade() -> some View {
        mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 28)
                Rectangle()
            }
            // A mask lays out inside the safe area unless told otherwise, and would cut a page
            // that runs to the screen's edge flat at the line.
            .ignoresSafeArea(.container, edges: .bottom)
        }
    }
}
