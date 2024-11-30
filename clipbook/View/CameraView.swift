import SwiftUI
import AVFoundation


//MARK: Camera View

struct CameraView: View {
    // changes in here will automatically rerender UI
    @EnvironmentObject var cameraModel: CameraViewModel // main interface, injects viewmodel into cameraview.. able to acces stuff from CameraViewModel
    
    // MARK: CameraPreview attached with progress bar
    var body: some View{
        
        // MARK: CameraPreview attached with progress bar
        GeometryReader{proxy in
                let size = proxy.size
            
                CameraPreview(size: size) // shows the CameraPreview through this, but also adds the progress bar above it
                    .environmentObject(cameraModel) // access to cameraModel still through this object
            
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.black.opacity(0.25))
                    
                    Rectangle()
                        .fill(.red) // progress bar color
                        .frame(width: size.width * (cameraModel.recordedDuration / cameraModel.maxDuration)) // size of progress bar calculations
                }
                .frame(height: 8) //height of progress bar
                .frame(maxHeight: .infinity,alignment: .top) // decides max height
                
            }
            .onAppear(perform: cameraModel.checkPermission)
            .alert(isPresented: $cameraModel.alert) {
                Alert(title: Text("Please Enable cameraModel Access Or Microphone Acess!!"))
            }
            // functionality for progress bar// functionality for progress bar
            .onReceive(Timer.publish(every: 0.01, on: .main, in: .common).autoconnect()) { _ in         // functionality for progress bar
                if cameraModel.recordedDuration <= cameraModel.maxDuration && cameraModel.isRecording{
                    cameraModel.recordedDuration += 0.01
                }
                
                if cameraModel.recordedDuration >= cameraModel.maxDuration && cameraModel.isRecording{ // functionality for stopping recording if reaches maxDuration
                    cameraModel.stopRecording() //stopping the recording!!
                    cameraModel.isRecording = false
                }
            }
    }
}

// MARK: Camera Preview
struct CameraPreview: UIViewRepresentable { // struct with implemented UIKit class to display camera live feed (UIViewRepresentable)
    
    @EnvironmentObject var cameraModel : CameraViewModel     // using the shared settings from CameraViewModel that was injected
    var size: CGSize // sets size for the preview to be shown correctly
    
    // function to make UI View for CameraPreview / size
    func makeUIView(context: Context) -> UIView {
        let view = UIView() // creates a UIView as a container
        cameraModel.preview = AVCaptureVideoPreviewLayer(session: cameraModel.session) // creates preview from default preview layer of that session
        cameraModel.preview.frame.size = size // match the size to the size of the preview default
        cameraModel.preview.videoGravity = .resizeAspectFill // fills the screen while maintaining aspect ration/high quality look of correct size
        view.layer.addSublayer(cameraModel.preview) // make the view have a layer over it so it's above the camera as a seperate section
        cameraModel.session.startRunning() // start the camera Preview to work
        return view
    }
    
    // if you want to change the look of the UI view, you'd do it here
    func updateUIView(_ uiView: UIView, context: Context) {
        
    }
}
