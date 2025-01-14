import SwiftUI
import AVFoundation

struct CameraView: View {
    @EnvironmentObject var cameraModel: CameraViewModel

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            
            ZStack(alignment: .topLeading) {
                // Camera Preview Layer
                CameraPreview(size: size)
                    .environmentObject(cameraModel)
                    .gesture(TapGesture(count: 2).onEnded {
                        cameraModel.switchCamera()  // Call to switch camera on double tap		
                    })
                
                // Progress Bar
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.black.opacity(0.25)) // Background of the progress bar

                    Rectangle()
                        .fill(Color.red) // Progress bar color
                        .frame(width: size.width * cameraModel.progress)  // Progress bar width based on current progress
                }
                .frame(height: 8)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .onAppear(perform: cameraModel.checkPermission)  // Start camera setup when view appears
            .onReceive(Timer.publish(every: 0.01, on: .main, in: .common).autoconnect()) { _ in
                if cameraModel.isRecording {
                    let totalDuration = cameraModel.clipTimes.reduce(0, +) + cameraModel.recordedDuration
                    // Ensure progress bar reflects accurate total duration
                    if totalDuration >= cameraModel.maxDuration {
                        cameraModel.stopRecording()
                        cameraModel.isRecording = false
                    } else {
                        // Ensure recordedDuration is updated smoothly
                        cameraModel.recordedDuration += 0.01
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                // Stop recording and pause progress bar when app moves to background
                if cameraModel.isRecording {
                    cameraModel.stopRecording()
                    cameraModel.isRecording = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                // Stop recording and pause progress bar when app is terminated
                if cameraModel.isRecording {
                    cameraModel.stopRecording()
                    cameraModel.isRecording = false
                }
            }
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    @EnvironmentObject var cameraModel: CameraViewModel
    var size: CGSize

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        cameraModel.preview = AVCaptureVideoPreviewLayer(session: cameraModel.session)
        cameraModel.preview.frame.size = size
        cameraModel.preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(cameraModel.preview)
        cameraModel.session.startRunning()
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) { }
}
