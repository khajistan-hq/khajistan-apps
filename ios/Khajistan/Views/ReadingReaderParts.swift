import SwiftUI
import UIKit

// The reader's pieces: the zoomable page or spread, the scrubber, and the pages grid.

/// What a tap on the page asked for. The reader decides what each means for the issue's direction.
enum ReaderTap {
    case leftEdge, rightEdge, middle
}

/// The page, or two facing pages, in a scroll view: pinch and double-tap zoom to 6x, pan when
/// zoomed. A single tap reports where it landed (edges turn, the middle shows the controls); a
/// horizontal drag on the unzoomed page follows the finger and turns on release. `zoomed` tells the
/// reader when the page is zoomed; setting it true from outside (VoiceOver) zooms the middle in.
struct ZoomablePage: UIViewRepresentable {
    /// Left to right as they lie on screen: one page, or a spread already in reading order.
    let images: [UIImage]
    @Binding var zoomed: Bool
    var tapped: (ReaderTap) -> Void
    var dragged: (CGFloat) -> Void
    var released: (CGFloat, CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 6
        scroll.bouncesZoom = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.backgroundColor = .clear
        scroll.contentInsetAdjustmentBehavior = .never
        let spread = SpreadView()
        spread.translatesAutoresizingMaskIntoConstraints = false
        spread.images = images
        scroll.addSubview(spread)
        NSLayoutConstraint.activate([
            spread.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            spread.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            spread.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            spread.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            spread.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            spread.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        context.coordinator.spread = spread
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
        // A single tap waits out a double tap, as in Apple Books.
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.require(toFail: doubleTap)
        scroll.addGestureRecognizer(tap)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.panned(_:)))
        pan.delegate = context.coordinator
        scroll.addGestureRecognizer(pan)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.spread?.images.elementsEqual(images, by: ===) == false {
            context.coordinator.spread?.images = images
        }
        if !zoomed, scroll.zoomScale > 1.01 {
            scroll.setZoomScale(1, animated: false)
        } else if zoomed, scroll.zoomScale <= 1.01 {
            context.coordinator.zoom(scroll, about: CGPoint(x: scroll.bounds.midX, y: scroll.bounds.midY))
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var parent: ZoomablePage
        weak var spread: SpreadView?

        init(_ parent: ZoomablePage) { self.parent = parent }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { spread }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            let now = scrollView.zoomScale > 1.01
            if now != parent.zoomed { parent.zoomed = now }
        }

        func zoom(_ scroll: UIScrollView, about point: CGPoint) {
            let scale: CGFloat = 2.5
            let size = CGSize(width: scroll.bounds.width / scale, height: scroll.bounds.height / scale)
            scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }

        @objc func doubleTapped(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView else { return }
            if scroll.zoomScale > 1.01 {
                scroll.setZoomScale(1, animated: true)
            } else {
                zoom(scroll, about: gesture.location(in: spread))
            }
        }

        /// The outer quarter on each side turns; the rest shows or hides the controls. A zoomed
        /// page only shows or hides them, so a tap never throws away the place zoomed to.
        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView, scroll.bounds.width > 0 else { return }
            guard scroll.zoomScale <= 1.01 else { return parent.tapped(.middle) }
            let x = gesture.location(in: scroll).x / scroll.bounds.width
            parent.tapped(x < 0.25 ? .leftEdge : x > 0.75 ? .rightEdge : .middle)
        }

        @objc func panned(_ gesture: UIPanGestureRecognizer) {
            let dx = gesture.translation(in: nil).x
            switch gesture.state {
            case .changed: parent.dragged(dx)
            case .ended: parent.released(dx, gesture.velocity(in: nil).x)
            case .cancelled, .failed: parent.released(0, 0)
            default: break
            }
        }

        /// The turning drag starts only on an unzoomed page and only sideways; a zoomed page pans.
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer, let scroll = pan.view as? UIScrollView else { return true }
            guard scroll.zoomScale <= 1.01 else { return false }
            let velocity = pan.velocity(in: nil)
            return abs(velocity.x) > abs(velocity.y) * 1.5
        }

        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            other is UIPinchGestureRecognizer
        }
    }
}

/// One page or two facing pages, fitted whole to the view at one height and touching at the fold.
/// Nothing is cropped or redrawn: each picture is shown as stored, scaled.
final class SpreadView: UIView {
    var images: [UIImage] = [] {
        didSet {
            while views.count < images.count {
                let view = UIImageView()
                view.contentMode = .scaleToFill
                addSubview(view)
                views.append(view)
            }
            for (index, view) in views.enumerated() {
                view.image = index < images.count ? images[index] : nil
                view.isHidden = index >= images.count
            }
            setNeedsLayout()
        }
    }
    private var views: [UIImageView] = []

    override func layoutSubviews() {
        super.layoutSubviews()
        let ratios = images.map { $0.size.height > 0 ? $0.size.width / $0.size.height : 1 }
        let total = ratios.reduce(0, +)
        guard total > 0, bounds.width > 0, bounds.height > 0 else { return }
        let height = min(bounds.height, bounds.width / total)
        var x = (bounds.width - height * total) / 2
        let y = (bounds.height - height) / 2
        for (index, ratio) in ratios.enumerated() {
            views[index].frame = CGRect(x: x, y: y, width: height * ratio, height: height)
            x += height * ratio
        }
    }
}

/// A page at the small size, if the page server allows it to this viewer; nothing otherwise.
/// A page held behind its content warning (`curtained`) is not drawn small either: the warning is
/// the reader's own (client-side), so the server hands the small picture over regardless.
struct PageThumb: View {
    let issue: RRIssue
    let stored: Int
    var curtained = false
    @Environment(AppModel.self) private var model
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .overlay { if let image, !curtained { Image(uiImage: image).resizable().aspectRatio(contentMode: .fit) } }
            .accessibilityHidden(true)
            .task(id: "\(stored)|\(curtained)") {
                image = curtained ? nil : await model.reading.thumbnail(issue, stored: stored)
            }
    }
}

/// The page scrubber, drawn in the house's own ink: the system slider's knob is white, and the
/// house has no white. The line fills to the knob, so it is also how far into the issue you are,
/// and it runs the way the pages do. VoiceOver adjusts it a page at a time.
struct PageScrubber: View {
    @Binding var page: Double
    let pages: Int
    let rightToLeft: Bool
    var scrubbing: (Bool) -> Void = { _ in }
    let commit: () -> Void
    @Environment(\.palette) private var palette
    @State private var held = false

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width - 22, 1)
            let fraction = pages > 1 ? (page - 1) / Double(pages - 1) : 0
            let x = (rightToLeft ? 1 - fraction : fraction) * width
            ZStack(alignment: .leading) {
                Rectangle().fill(palette.faint).frame(height: 2).padding(.horizontal, 11)
                Rectangle().fill(palette.accent)
                    .frame(width: rightToLeft ? width - x : x, height: 2)
                    .offset(x: rightToLeft ? 11 + x : 11)
                Rectangle().fill(palette.accent).frame(width: 22, height: 22).offset(x: x)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !held { held = true; scrubbing(true) }
                    var f = min(max((value.location.x - 11) / width, 0), 1)
                    if rightToLeft { f = 1 - f }
                    page = (1 + f * Double(pages - 1)).rounded()
                }
                .onEnded { _ in
                    held = false
                    scrubbing(false)
                    commit()
                })
        }
        .frame(height: 44)
        .accessibilityElement()
        .accessibilityLabel("Page")
        .accessibilityValue("\(Int(page)) of \(pages)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: page = min(page + 1, Double(pages))
            case .decrement: page = max(page - 1, 1)
            @unknown default: break
            }
            commit()
        }
    }
}

/// Every page of the issue as a small picture, the way Kindle's Page Flip lays them out: the page
/// being read on the lift plate, marked pages with the ribbon, and the marks listed above. The page
/// server is asked about the pictures in runs at the small size; a page it does not allow this
/// viewer shows its number and no picture.
struct PagesGrid: View {
    let issue: RRIssue
    let pages: Int
    let map: [Int]?
    let current: Int
    let marks: [Int]
    let rightToLeft: Bool
    /// A page behind its content warning, not yet shown: its number only.
    let curtained: (Int) -> Bool
    let choose: (Int) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Pages").kjName(KJType.title)
                Spacer()
                Button(kicker: "Done") { dismiss() }.accessibilityIdentifier("rrGridDone")
            }
            .padding(.horizontal, KJLayout.inset)
            .padding(.top, 12)
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if !marks.isEmpty { bookmarks }
                        grid
                    }
                    .padding(.horizontal, KJLayout.inset)
                    .padding(.vertical, 12)
                }
                .onAppear { reader.scrollTo(current, anchor: .center) }
            }
        }
        .foregroundStyle(palette.ink)
        .background(palette.ground.ignoresSafeArea())
        .task(id: issue.key) {
            // Nearest the page being read first, so the grid fills where you are.
            let order = (1...pages).sorted { abs($0 - current) < abs($1 - current) }
            await model.reading.signThumbnails(issue, stored: order.map { RRPageMap.stored($0, map: map) })
        }
    }

    private var bookmarks: some View {
        VStack(alignment: .leading, spacing: 6) {
            Kicker("Bookmarks")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(marks, id: \.self) { page in
                        Button { choose(page) } label: {
                            Label("Page \(page)", systemImage: "bookmark.fill").kjSmall()
                        }
                        .buttonStyle(HouseButtonStyle(padding: EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)))
                        .accessibilityIdentifier("rrMark-\(page)")
                    }
                }
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12, alignment: .top)], spacing: 16) {
            ForEach(1...pages, id: \.self) { page in
                Button { choose(page) } label: {
                    VStack(spacing: 4) {
                        PageThumb(issue: issue, stored: RRPageMap.stored(page, map: map), curtained: curtained(page)).frame(height: 132)
                        HStack(spacing: 3) {
                            if marks.contains(page) { Image(systemName: "bookmark.fill").font(.caption2) }
                            Text("\(page)").kjSmall().monospacedDigit()
                        }
                        .foregroundStyle(page == current ? palette.accent : palette.ink)
                    }
                    .padding(6)
                    .background(page == current ? palette.lift : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .id(page)
                .accessibilityLabel("Page \(page)" + (marks.contains(page) ? ", bookmarked" : ""))
                .accessibilityAddTraits(page == current ? .isSelected : [])
                .accessibilityIdentifier("rrGridPage-\(page)")
            }
        }
        // A right-to-left issue lays its pages out from the right, as its own pages run.
        .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
    }
}
