//
//  YoutubePlayerView.swift
//  KneeRecoveryApp
//
//  Created by wfs on 2025/4/3.
//

import SwiftUI
import YoutubeKit

struct YoutubePlayerView: UIViewRepresentable {
    let videoID: String

    func makeUIView(context: Context) -> YTSwiftyPlayer {
        let player = YTSwiftyPlayer(frame: .zero, playerVars: [.videoID(videoID), .autoplay(false), .playsInline(true)])
        player.autoplay = false
//        player.delegate = context.coordinator
        player.loadDefaultPlayer()
        return player
    }

    func updateUIView(_ uiView: YTSwiftyPlayer, context: Context) {
        
        
    }
}
