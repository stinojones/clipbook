import SwiftUI
import AVFoundation


//MARK: Camera View

struct CameraView: View {
    // main interface, injects viewmodel into cameraview.. able to acces stuff from CameraViewModel
    @EnvironmentObject var cameraModel: CameraViewModel
    
    // CameraPreview attached with progress bar
    var body: some View{
        
        // CameraPreview attached with progress bar
        GeometryReader{proxy in
                let size = proxy.size
            
                // shows the CameraPreview through this, but also adds the progress bar above it
                CameraPreview(size: size)
                    // access to cameraModel still through this object
                    .environmentObject(cameraModel)
            
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.black.opacity(0.25))
                    
                    Rectangle()
                        // progress bar color
                        .fill(.red)
                        // size of progress bar calculations
                        .frame(width: size.width * (cameraModel.recordedDuration / cameraModel.maxDuration))
                }
                //height of progress bar
                .frame(height: 8)
                // engrained in top of screen
                .frame(maxHeight: .infinity,alignment: .top)
                
            }
            .onAppear(perform: cameraModel.checkPermission)
            .alert(isPresented: $cameraModel.alert) {
                Alert(title: Text("Please Enable cameraModel Access Or Microphone Acess!!"))
            }
            // functionality for progress bar
            .onReceive(Timer.publish(every: 0.01, on: .main, in: .common).autoconnect()) { _ in
                if cameraModel.recordedDuration <= cameraModel.maxDuration && cameraModel.isRecording{
                    cameraModel.recordedDuration += 0.01
                }
                // stopping recording if reaches maxDuration
                if cameraModel.recordedDuration >= cameraModel.maxDuration && cameraModel.isRecording{
                    cameraModel.stopRecording()
                    cameraModel.isRecording = false
                }
            }
    }
}

// Camera Preview
// struct with implemented UIKit class to display camera live feed (UIViewRepresentable)
struct CameraPreview: UIViewRepresentable {
    
    
    // using the shared settings from CameraViewModel that was injected
    @EnvironmentObject var cameraModel : CameraViewModel
    
    
    // sets size for the preview to be shown correctly
    var size: CGSize
    

    // function to make UI View for CameraPreview / size
    func makeUIView(context: Context) -> UIView {
        
        
        // creates a UIView as a container
        let view = UIView()
        
        
        // creates preview from default preview layer of that session
        cameraModel.preview = AVCaptureVideoPreviewLayer(session: cameraModel.session)
        
        
        // match the size to the size of the preview default
        cameraModel.preview.frame.size = size
        
        
        // fills the screen while maintaining aspect ration/high quality look of correct size
        cameraModel.preview.videoGravity = .resizeAspectFill
        
        
        // make the view have a layer over it so it's above the camera as a seperate section
        view.layer.addSublayer(cameraModel.preview)
        
        
        // start the camera Preview to work
        cameraModel.session.startRunning()
        return view
    }
    
    
    
    // if you want to change the look of the UI view, you'd do it here
    func updateUIView(_ uiView: UIView, context: Context) {
        
    }
}
