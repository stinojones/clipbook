import SwiftUI
import AVKit

struct Home: View {
    @StateObject var cameraModel = CameraViewModel()
    @ObservedObject var videoManager = VideoManager()
    @State private var isLoading: Bool = false // Tracks loading state
    
    var body: some View {
        ZStack(alignment: .bottom) {
            CameraView()
                .environmentObject(cameraModel)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .padding(.top, 10)
                .padding(.bottom, 30)
            
            // Controls ZStack
            HStack(alignment: .center, spacing: 10) {
                
                // Undo Button
                Button {
                    if cameraModel.clipCount > 0 {
                        videoManager.undoLastClip()
                        cameraModel.undoLastClip()
                    }
                } label: {
                    Group {
                        if videoManager.hasClipsInDirectory() {
                            Label {
                                Image(systemName: "arrow.uturn.backward.circle")
                                    .font(.callout)
                            } icon: {}
                            .foregroundColor(.black)
                        } else {
                            Image(systemName: "arrow.uturn.backward.circle")
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background {
                        Circle()
                            .fill(.white)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading)
                .opacity(cameraModel.isRecording || UserDefaults.standard.integer(forKey: "clipCount") <= 0 ? 0 : 1)
                
                // Recording Button
                Button {
                    if cameraModel.isRecording {
                        cameraModel.stopRecording()
                    } else {
                        cameraModel.startRecording()
                    }
                } label: {
                    Image("Reels")
                        .resizable()
                        .renderingMode(.template)
                        .aspectRatio(contentMode: .fit)
                        .foregroundColor(.black)
                        .opacity(cameraModel.isRecording ? 0 : 1)
                        .padding(12)
                        .frame(width: 60, height: 60)
                        .background {
                            Circle()
                                .stroke(cameraModel.isRecording ? .clear : .black)
                        }
                        .padding(6)
                        .background {
                            Circle()
                                .fill(cameraModel.isRecording ? .red : .white)
                        }
                }
                
                // Preview Button
                Button {
                    if videoManager.hasClipsInDirectory() && !isLoading {
                        isLoading = true // Start loading
                        videoManager.mergeClipsForPreview { previewURL in
                            DispatchQueue.main.async {
                                if let previewURL = previewURL {
                                    videoManager.previewURL = previewURL
                                    cameraModel.showPreview.toggle()
                                } else {
                                    print("Failed to create preview URL.")
                                }
                                isLoading = false // End loading
                            }
                        }
                    }
                } label: {
                    Group {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .black)) // Black tinted loading indicator
                        } else if videoManager.hasClipsInDirectory() {
                            Label {
                                Image(systemName: "play.circle")
                                    .font(.callout)
                            } icon: {}
                            .foregroundColor(.black)
                        } else {
                            Image(systemName: "play.circle")
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background {
                        Circle()
                            .fill(.white)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing)
                .opacity(cameraModel.isRecording || UserDefaults.standard.integer(forKey: "clipCount") <= 0 ? 0 : 1)
                .disabled(isLoading) // Disable while loading
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 30)
        }
        .sheet(isPresented: $cameraModel.showPreview) {
            FinalPreview(cameraModel: cameraModel, videoManager: videoManager)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if value.translation.height < 0 {
                                // Optionally handle upward swipes or other gestures
                            }
                        }
                        .onEnded { value in
                            if value.translation.height > 100 { // Swipe threshold
                                cameraModel.showPreview.toggle() // Dismiss the preview
                            }
                        }
                )
                .preferredColorScheme(.dark)
        }
        .animation(.easeInOut, value: cameraModel.showPreview)
    }
}

struct FinalPreview: View {
    @ObservedObject var cameraModel: CameraViewModel
    var videoManager: VideoManager
    @State private var player: AVPlayer?
    @State private var isPlaying: Bool = true
    
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            if let previewURL = videoManager.previewURL {
                VideoPlayer(player: player)
                    .onAppear {
                        // Initialize player and start playback automatically
                        if player == nil {
                            player = AVPlayer(url: previewURL)
                            player?.play()
                        }
                    }
                    .onChange(of: isPlaying) { newValue in
                        if newValue {
                            player?.play()
                        } else {
                            player?.pause()
                        }
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .onDisappear {
                        player?.pause() // Pause the video when it disappears
                    }
            } else {
                Text("Loading preview...")
                    .foregroundColor(.white)
            }
        }
    }
}

#Preview {
    Home()
}
