//
//  ContentView.swift
//  youtube-music-player
//
//  Created by Jem on 12/1/25.
//

import SwiftUI

struct ContentView: View {
    @State private var webViewModel = YouTubeMusicViewModel()
    @State private var mediaKeyHandler = MediaKeyHandler()
    @State private var discordRPC = DiscordRPC()

    var body: some View {
        VStack(spacing: 0) {
            // Window header for dragging
            WindowHeader()
                .frame(height: 32)

            YouTubeMusicWebView(viewModel: webViewModel)
        }
        .ignoresSafeArea()
        .onAppear {
            mediaKeyHandler.setViewModel(webViewModel)
            setupDiscordPresence()
        }
    }

    private func setupDiscordPresence() {
        let existingCallback = webViewModel.onTrackChange

        webViewModel.onTrackChange = { title, artist, artworkUrl, isPlaying in
            // Call existing callback (for Now Playing)
            existingCallback?(title, artist, artworkUrl, isPlaying)

            // Update Discord presence
            if let title = title, let artist = artist, isPlaying {
                discordRPC.updatePresence(
                    title: title,
                    artist: artist,
                    artworkUrl: artworkUrl?.absoluteString
                )
            } else if !isPlaying {
                discordRPC.clearPresence()
            }
        }
    }
}

struct WindowHeader: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = DraggableHeaderView()
        view.wantsLayer = true
        // Match YouTube Music's dark header (#212121)
        view.layer?.backgroundColor = NSColor(red: 0.129, green: 0.129, blue: 0.129, alpha: 1.0).cgColor
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

class DraggableHeaderView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

#Preview {
    ContentView()
}
