import AVKit
import SwiftUI

/// This surface exists only when AppModel holds a provisioned runtime. Its only playback
/// action opens the validated private asset in-app; no URL, preview, share or export is exposed.
struct OfflineFilmLibraryView: View {
    @Bindable var runtime: OfflineFilmRuntime
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var playing: OfflineProtectedPlayback?
    @State private var opening: UUID?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                if !runtime.active {
                    Text("Sign in again to check your offline films.")
                } else if runtime.rows.isEmpty {
                    Text("Films you save in the Screening Room appear here.")
                }
                ForEach(runtime.rows, id: \.id) { row in
                    OfflineFilmLibraryRow(row: row, opening: opening == row.id,
                        play: { play(row) }, pause: { action { try runtime.library.pause(row.id) } },
                        resume: { action { try runtime.library.resume(row.id) } },
                        remove: { action { try runtime.remove(row.id) } })
                        .listRowBackground(palette.ground)
                }
                if let message = message ?? runtime.errorMessage {
                    Text(message).foregroundStyle(palette.faint).accessibilityIdentifier("offlineFilmError")
                }
            }
            .scrollContentBackground(.hidden).background(palette.ground)
            .navigationTitle("Offline films")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task {
            do { try await runtime.restore() }
            catch { message = safeMessage(error) }
        }
        .fullScreenCover(item: $playing) { playback in
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                VideoPlayer(player: playback.player).ignoresSafeArea()
                Button { playback.stop(); playing = nil } label: {
                    Label("Close", systemImage: "xmark.circle.fill").padding(12)
                }.buttonStyle(.borderedProminent).padding()
            }
            .onAppear { playback.player.play() }
            .onDisappear { playback.stop() }
        }
    }

    private func action(_ work: () throws -> Void) {
        message = nil
        do { try work() } catch { message = safeMessage(error) }
    }

    private func play(_ row: OfflineFilmLibraryRecord) {
        guard opening == nil else { return }
        opening = row.id; message = nil
        Task {
            defer { opening = nil }
            do {
                let playback = try await runtime.play(row.id)
                playback.onFailure = { error in message = safeMessage(error); playing = nil }
                playing = playback
            } catch { message = safeMessage(error) }
        }
    }

    private func safeMessage(_ error: Error) -> String {
        (error as? OfflineFilmError)?.errorDescription ?? "This offline film could not be opened. Connect and try again."
    }
}

#if DEBUG
/// Interface-only fixture. It cannot construct a runtime, request a key or download media.
struct OfflineFilmLibraryFixtureView: View {
    @Environment(\.palette) private var palette
    @State private var phase: OfflineFilmLibraryRecord.Phase = .downloading
    @State private var action = "Local interface fixture — no media"
    private func row(_ title: String, _ phase: OfflineFilmLibraryRecord.Phase) -> OfflineFilmLibraryRecord {
        let now = Date()
        return OfflineFilmLibraryRecord(id: UUID(), grant: OfflineFilmGrant(entitlementID: UUID(),
            accountID: "fixture", deviceID: UUID(), filmHandle: "fixture", assetVersion: "fixture", kind: .purchase,
            issuedAt: now, refreshBy: now.addingTimeInterval(3600), startBy: nil, playbackEndsAt: nil, playbackDuration: nil),
            keyIdentifier: "skd://fixture", title: title, phase: phase, taskIdentifier: nil, packagePath: nil)
    }
    var body: some View {
        List {
            Text("Offline films").font(.largeTitle.bold()).listRowBackground(palette.ground)
            OfflineFilmLibraryRow(row: row("Filmfarsi — Volume One", phase), opening: false,
                play: { action = "Play selected" }, pause: { phase = .paused; action = "Paused" },
                resume: { phase = .downloading; action = "Resumed" }, remove: { action = "Remove selected" })
                .listRowBackground(palette.ground)
            OfflineFilmLibraryRow(row: row("A saved film with a longer title", .ready), opening: false,
                play: { action = "Play selected" }, pause: {}, resume: {}, remove: { action = "Remove selected" })
                .listRowBackground(palette.ground)
            Text(action).accessibilityIdentifier("offlineFixtureAction").listRowBackground(palette.ground)
        }
        .scrollContentBackground(.hidden).background(palette.ground)
    }
}
#endif

/// Factored for local UI fixtures; fixture rows cannot construct an AVPlayer or license.
struct OfflineFilmLibraryRow: View {
    @Environment(\.palette) private var palette
    let row: OfflineFilmLibraryRecord
    let opening: Bool
    let play: () -> Void
    let pause: () -> Void
    let resume: () -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(row.title).font(.headline).fixedSize(horizontal: false, vertical: true)
            Text(status).font(.subheadline).foregroundStyle(palette.faint)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { controls }
                VStack(alignment: .leading, spacing: 12) { controls }
            }
        }
        .padding(.vertical, 8)
        .buttonStyle(HouseButtonStyle())
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var controls: some View {
        if row.phase == .ready {
            Button(opening ? "Opening…" : "Play", action: play).disabled(opening)
                .accessibilityLabel("Play \(row.title)")
        } else if row.phase == .downloading {
            Button("Pause", action: pause).accessibilityLabel("Pause \(row.title)")
        } else if row.phase == .paused {
            Button("Resume", action: resume).accessibilityLabel("Resume \(row.title)")
        }
        Button(row.phase == .removing ? "Retry removal" : "Remove", role: .destructive, action: remove)
            .accessibilityLabel("Remove \(row.title) from this device")
    }

    private var status: String {
        switch row.phase {
        case .downloading: return "Downloading"
        case .paused: return "Paused"
        case .verifying: return "Finishing download"
        case .ready: return "Saved in this app"
        case .failed: return "Download unavailable. Remove it and save it again."
        case .removing: return "Removing from this device"
        }
    }
}
