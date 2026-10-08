import AVKit
import SwiftUI

/// What every full-screen player shares: the close control at the top, the panel at the bottom,
/// and the overlay that wakes on a tap and goes 2.6 seconds into playback.
struct PlayerTopBar: View {
    let leading: [String]
    let trailing: [String]
    let close: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 0) {
            Button(action: close) {
                Image(systemName: "xmark").font(.system(.body, weight: .bold)).frame(width: 44, height: 40)
            }
            .buttonStyle(HouseButtonStyle(padding: EdgeInsets()))
            .environment(\.palette, palette.onBandPlate)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("closePlayer")
            StatusBand(leading: leading, trailing: trailing)
                .padding(.leading, -KJLayout.inset + 4)
        }
        .padding(.leading, 6)
        .background(palette.band, ignoresSafeAreaEdges: [.horizontal, .top])
    }
}

/// The play/pause control and AirPlay, in the panel's ink.
struct TransportRow: View {
    let isPlaying: Bool
    let toggle: () -> Void
    var back: (() -> Void)?
    var forward: (() -> Void)?
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 4) {
            if let back {
                Button(action: back) { Image(systemName: "gobackward.30").font(.title3.weight(.bold)).frame(width: 48, height: 44) }
                    .buttonStyle(HouseButtonStyle(padding: EdgeInsets()))
                    .accessibilityLabel("Back 30 seconds")
            }
            Button(action: toggle) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill").font(.title2.weight(.bold)).frame(width: 52, height: 44)
            }
            .buttonStyle(HouseButtonStyle(padding: EdgeInsets()))
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            .accessibilityIdentifier("playPause")
            if let forward {
                Button(action: forward) { Image(systemName: "goforward.30").font(.title3.weight(.bold)).frame(width: 48, height: 44) }
                    .buttonStyle(HouseButtonStyle(padding: EdgeInsets()))
                    .accessibilityLabel("Forward 30 seconds")
            }
            Spacer(minLength: 0)
            AirPlayButton(tint: UIColor(palette.ink), active: UIColor(palette.accent))
                .frame(width: 44, height: 44)
                .accessibilityLabel("Audio and video output")
        }
        .padding(.leading, -14)
    }
}

struct AirPlayButton: UIViewRepresentable {
    let tint: UIColor
    let active: UIColor

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = true
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        view.tintColor = tint
        view.activeTintColor = active
    }
}

/// The overlay's timer: awake while a press is recent or the signal is not yet playing.
@MainActor @Observable
final class OverlayClock {
    var visible = true
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    func wake(settled: Bool) {
        withAnimation(.kj) { visible = true }
        hideTask?.cancel()
        guard settled, !Self.staysUp else { return }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { self?.visible = false }
        }
    }

    func toggle(settled: Bool) {
        if visible && settled {
            hideTask?.cancel()
            withAnimation(.easeOut(duration: 0.2)) { visible = false }
        } else {
            wake(settled: settled)
        }
    }

    func stop() { hideTask?.cancel() }

    /// `-kjcontrolsstay YES` keeps the controls up, so a UI test can reach them without racing the
    /// 2.6 s hide. Debug builds only.
    private static let staysUp: Bool = {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "kjcontrolsstay")
        #else
        return false
        #endif
    }()
}

extension View {
    /// Swipe up for the next channel, down for the previous one; a tap wakes the overlay.
    func channelGestures(step: @escaping (Int) -> Void, tap: @escaping () -> Void) -> some View {
        contentShape(Rectangle())
            .onTapGesture(perform: tap)
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        let dy = value.translation.height
                        guard abs(dy) > 60, abs(dy) > abs(value.translation.width) else { return }
                        step(dy < 0 ? 1 : -1)
                    }
            )
    }
}
