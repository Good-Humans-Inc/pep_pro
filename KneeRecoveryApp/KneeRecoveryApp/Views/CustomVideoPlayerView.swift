//
//  CustomVideoPlayerView.swift
//  KneeRecoveryApp
//
//  Created by wfs on 2025/4/4.
//


//import SwiftUI
//import AVKit
//
//struct CustomVideoPlayerView: UIViewControllerRepresentable {
//    let url: URL
//
//    func makeUIViewController(context: Context) -> AVPlayerViewController {
//        let player = AVPlayer(url: url)
//        let controller = AVPlayerViewController()
//        controller.player = player
//        controller.showsPlaybackControls = true // 显示播放/暂停/全屏按钮
//        // 播放一下再暂停，强制显示控制条
//         DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
//             player.play()
//             DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
//                 player.pause()
//             }
//         }
//        return controller
//    }
//
//    func updateUIViewController(_ playerController: AVPlayerViewController, context: Context) {
//        // 可在这里处理更新逻辑
//    }
//}

import SwiftUI
import AVKit

struct CustomVideoPlayerView: View {
    let url: URL
    @State private var player: AVPlayer?
    @State private var isPlaying = false

    var body: some View {
        ZStack {
            // 视频播放器
            VideoPlayerController(player: player)
                .onAppear {
                    player = AVPlayer(url: url)
                }
            
            // 自定义播放按钮
            if !isPlaying {
                Button(action: {
                    isPlaying.toggle()
                    player?.play()
                }) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(height: 300)
        .onDisappear {
            player?.pause()
        }
    }
}

// 包装 AVPlayerViewController
struct VideoPlayerController: UIViewControllerRepresentable {
    let player: AVPlayer?
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player // 必须设置 player
        controller.showsPlaybackControls = true // 显示系统控制条
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // 确保 player 更新
        if uiViewController.player != player {
            uiViewController.player = player
        }
    }
}
