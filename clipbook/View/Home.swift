import SwiftUI
import AVKit

struct Home: View {
    @StateObject var cameraModel = CameraViewModel()
    @ObservedObject var videoManager = VideoManager()
    
    var body: some View {
        ZStack(alignment: .bottom) {
            CameraView()
                // camera shape to record
                .environmentObject(cameraModel)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .padding(.top, 10)
                .padding(.bottom, 30)
            
            // controls zstack
            ZStack {
                
                // recording button
                Button {
                    if cameraModel.isRecording {
                        cameraModel.stopRecording()
                    } else {
                        cameraModel.startRecording()
                    }
                } label: {
                    // recording for red button, not recording for normal look
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
                    if videoManager.hasClipsInDirectory() { // Check if there are clips in the directory
                        if cameraModel.showPreview {
                            // Hide the preview
                            cameraModel.showPreview.toggle()
                        } else {
                            // Generate the preview if not already showing
                            videoManager.mergeClipsForPreview { previewURL in
                                if let previewURL = previewURL {
                                    print("Preview URL created: \(previewURL)")
                                    DispatchQueue.main.async {
                                        videoManager.previewURL = previewURL
                                        cameraModel.showPreview.toggle()
                                    }
                                } else {
                                    print("Failed to create preview URL.")
                                }
                            }
                        }
                    }
                } label: {
                    Group {
                        if videoManager.hasClipsInDirectory() { // Check if there are clips in the directory
                            Label {
                                Image(systemName: "chevron.right")
                                    .font(.callout)
                            } icon: {
                                Text("Preview")
                            }
                            .foregroundColor(.black)
                        } else {
                            Text("No Clips")
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background {
                        Capsule()
                            .fill(.white)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing)
                .opacity(cameraModel.isRecording || !videoManager.hasClipsInDirectory() ? 0 : 1) // Use hasClipsInDirectory to set opacity
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 10)
            .padding(.bottom, 30)
            
            // Delete Button (Clear Files)
            Button {
                videoManager.clearRecordedFiles()
                
            } label: {
                Image(systemName: "xmark")
                    .font(.title)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()
            .padding(.top)
        }

        .overlay {
            if let _ = videoManager.previewURL, cameraModel.showPreview {
                
                // saying what all bindings need to happen in previewURL
                FinalPreview(cameraModel: cameraModel, videoManager: videoManager)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut, value: cameraModel.showPreview)
        .preferredColorScheme(.dark)
    }

    
    
    struct FinalPreview: View {
        
        // Observing the model to access previewURL
        @ObservedObject var cameraModel: CameraViewModel
        
        // passing videomanager as a paramater
        var videoManager: VideoManager
        
        var body: some View {
            GeometryReader { proxy in
                let size = proxy.size
                if let previewURL = videoManager.previewURL {
                    VideoPlayer(player: AVPlayer(url: previewURL))
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            Button {
                                
                                // Use cameraModel.showPreview
                                cameraModel.showPreview.toggle()
                                
                            } label: {
                                Label {
                                    Text("Back")
                                } icon: {
                                    Image(systemName: "chevron.left")
                                }
                                .foregroundColor(.white)
                            }
                        }
                } else {
                    Text("Loading preview...")
                        .foregroundColor(.white)
                }
            }
        }
    }
}

#Preview {
    Home()
}

