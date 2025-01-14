import SwiftUI
import AVKit
import Photos

struct Home: View {
    @StateObject var cameraModel = CameraViewModel()
    @ObservedObject var videoManager = VideoManager()
    
    
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
                        cameraModel.undoTempvideo()
                    }
                } label: {
                    Group {
                            Label {
                                Image(systemName: "arrow.uturn.backward.circle")
                                    .font(.callout)
                            } icon: {}
                            .foregroundColor(.black)
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
                    if cameraModel.previewURL != nil {
                        cameraModel.showPreview.toggle()
                    }
                } label: {
                    Group {
                        if cameraModel.previewURL == nil && !cameraModel.recordedURLs.isEmpty {
                            ProgressView()
                                .tint(.black)
                        } else if let _ = cameraModel.previewURL {
                            // If previewURL exists, show play icon and automatically toggle on completion
                            Image(systemName: "play.circle")
                                .foregroundColor(.black)
                        } else {
                            Image(systemName: "play.circle")
                                .foregroundColor(.black)
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
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 30)
        }
        .sheet(isPresented: $cameraModel.showPreview) {
            FinalPreview(cameraModel: cameraModel)
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
    @State private var player: AVPlayer?
    @State private var isPlaying: Bool = true
    @State private var saveSuccessMessage: String?
    
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                if let previewURL = cameraModel.previewURL {
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
                
                // Save button in the top-right corner
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            saveVideoToPhotoAlbum(url: cameraModel.previewURL)
                        }) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.title)
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .padding()
                    }
                    Spacer()
                }
                
                // Show success message
                if let message = saveSuccessMessage {
                    Text(message)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                        .transition(.opacity)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation {
                                    saveSuccessMessage = nil
                                }
                            }
                        }
                }
            }
        }
    }
    
    // Helper function to save the video to the photo album
    func saveVideoToPhotoAlbum(url: URL?) {
        guard let url = url else { return }
        
        // Prompt the user for photo library access
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                // Save video to photo library
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }) { success, error in
                    DispatchQueue.main.async {
                        if success {
                            saveSuccessMessage = "Clip Saved!"
                        } else {
                            saveSuccessMessage = "Failed to save video."
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    saveSuccessMessage = "Photo Library access denied."
                }
            }
        }
    }
}

#Preview {
    Home()
}
