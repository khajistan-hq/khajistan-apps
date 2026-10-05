#if DEBUG
import SwiftUI

/// Debug builds only: a sound programme played straight from a URL, with the dancer, for the UI
/// tests. Khajistan Transmission needs the preview password and a signed-in account before
/// tv-play issues anything, and neither is the tests' to use; this plays one of channel 2's own
/// public storage mixes through the same PlayerController, the same tap and the same
/// DancerLayer, joined part-way through as a transmission is.
///
///     -kjsoundtest <https URL>   -kjsoundtestat <seconds>
struct SoundCheckView: View {
    let url: URL
    let start: Double
    @State private var controller = PlayerController()
    @Environment(\.palette) private var palette

    static var requested: SoundCheckView? {
        guard let text = UserDefaults.standard.string(forKey: "kjsoundtest"), let url = URL(string: text),
              url.scheme == "https" else { return nil }
        return SoundCheckView(url: url, start: UserDefaults.standard.double(forKey: "kjsoundtestat"))
    }

    var body: some View {
        ZStack {
            palette.ground.ignoresSafeArea()
            DancerLayer(controller: controller) {
                VStack(spacing: 24) {
                    Kicker("Channel 2 \u{00B7} sound only")
                    Text(url.deletingPathExtension().lastPathComponent).kjDisplay().multilineTextAlignment(.center)
                }
                .padding(.horizontal, KJLayout.inset)
            }
        }
        .task {
            controller.attach(url: url, seekTo: start, title: "Sound check", subtitle: nil, listen: true)
        }
    }
}
#endif
