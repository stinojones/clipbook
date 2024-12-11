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
                
                // Progress Bar
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.black.opacity(0.25)) // Background of the progress bar

                    Rectangle()
                        .fill(.red) // Progress bar color
                        .frame(width: size.width * cameraModel.progress)  // Progress bar width based on current progress
                }
                .frame(height: 8)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .onAppear(perform: cameraModel.checkPermission)  // Start camera setup when view appears
//        .alert(isPresented: $cameraModel.alert) {
//            Alert(title: Text("Please Enable Camera or Microphone Access!"))
//        } alert if you want later
        .onReceive(Timer.publish(every: 0.01, on: .main, in: .common).autoconnect()) { _ in
            if cameraModel.isRecording {
                let totalDuration = cameraModel.clipTimes.reduce(0, +) + cameraModel.recordedDuration
                
                // Debug prints to check if the totalDuration aligns with expected progress
                print("Total Duration: \(totalDuration)")
                print("Progress: \(cameraModel.progress)")

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
