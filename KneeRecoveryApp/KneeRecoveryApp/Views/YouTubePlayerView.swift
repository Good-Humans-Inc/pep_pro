//
//  YouTubePlayerView.swift
//  KneeRecoveryApp
//
//  Created by wfs on 2025/4/3.
//


import SwiftUI
import YouTubeiOSPlayerHelper

struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String
    class Coordinator: NSObject, YTPlayerViewDelegate {
        var parent: YouTubePlayerView
        init(_ parent: YouTubePlayerView) {
            self.parent = parent
        }

        func playerViewDidBecomeReady(_ playerView: YTPlayerView) {
            print("YouTube Player 准备就绪")
            playerView.playVideo()
        }
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    func makeUIView(context: Context) -> YTPlayerView {
        let playerView = YTPlayerView()
        playerView.delegate = context.coordinator
        
//        AIzaSyAxESo4ewt-Dd7D9F3txI6Wi969WhBfU8I
        
        let playerVars: [String: Any] = [
            "autoplay": 0,  // 禁用自动播放
            "controls": 1,  // 显示控制栏
            "playsinline": 1 // 允许内嵌播放
        ]
        playerView.load(withVideoId:videoID, playerVars: playerVars)
        
//        playerView.load(withVideoId: videoID)
        return playerView
    }

    func updateUIView(_ uiView: YTPlayerView, context: Context) {
        
    }
}
