import SwiftUI
import AVFoundation // used for handling audiovisual media

// nso needed for avfoundation, avcapturefileoutputrecordingdelegate - handle events during video recording
class CameraViewModel: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    
    // object that manages camera input/output of current session
    @Published var session = AVCaptureSession()
    
    @Published var tempFileURL: URL?
    
    // bool to trigger alerts
    @Published var alert = false
    
    // object to handle video output
    @Published var output = AVCaptureMovieFileOutput()
    
    // defualt way to show live camerafeed
    @Published var preview: AVCaptureVideoPreviewLayer!
    
    //MARK: --------------Video Recording States------------
    
    // tracks if camera is recording
    @Published var isRecording: Bool = false
    
    // holds urls of recorded videos
    @Published var recordedURLs: [URL] = []
    
    // bool for showing preview or not
    @Published var showPreview: Bool = false
    
    //MARK: -----------Progress Bar----------------------
    
    // tracks how long video has been recording
    @Published var recordedDuration: CGFloat = 0
    
    // defines maximum recording duration
    @Published var maxDuration: CGFloat = 10
    
    // Video manager initialized
    private let videoManager = VideoManager()
    
    
    
    //MARK: methods
    
    // Handle Recording Output
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Error during recording: \(error.localizedDescription)")
            return
        }

        // Save the video to the Clips directory using VideoManager with a completion handler
        videoManager.saveVideo(tempURL: outputFileURL) { success, _ in
            if success {
                // Update hasClips after saving the video
                self.videoManager.updateHasClips()  // Ensure the hasClips state is updated
                
                // At this point, hasClips and previewURL have been updated in VideoManager
                print("Has Clips after saving: \(self.videoManager.hasClips)")
                
                if let previewURL = self.videoManager.previewURL {
                    print("Preview URL updated to: \(previewURL.path)")
                } else {
                    print("No preview URL available.")
                }
            } else {
                print("Failed to save video.")
            }
        }
    }
    
    
    // Recording Button functions
    func startRecording() {
        // Generate a unique temp file URL
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tempRecording_\(UUID().uuidString).mov")
        
        // Set the tempFileURL property so it can be accessed later
        self.tempFileURL = tempURL
        
        // Start recording to the temp file
        output.startRecording(to: tempURL, recordingDelegate: self)
        isRecording = true
    }
    
    
    func stopRecording() {
        output.stopRecording()
        isRecording = false
    }
    
    
    // Camera Setup
    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setUp()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { (status) in
                if status {
                    self.setUp()
                }
            }
        case .denied:
            self.alert.toggle()
        default:
            return
        }
    }
    
    
    // Camera Setup
    func setUp() {
        do {
            self.session.beginConfiguration()
            
            // MARK: ------------------------------decides if it's a 0.5 view--------------------------------
            guard let cameraDevice = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) else {
                print("Error: No ultrawidecamera found.")
                return
            }
            
            let videoInput = try AVCaptureDeviceInput(device: cameraDevice)
            let audioDevice = AVCaptureDevice.default(for: .audio)
            let audioInput = try AVCaptureDeviceInput(device: audioDevice!)
            
            if self.session.canAddInput(videoInput) && self.session.canAddInput(audioInput) {
                self.session.addInput(videoInput)
                self.session.addInput(audioInput)
            }
            
            if self.session.canAddOutput(self.output) {
                self.session.addOutput(self.output)
            }
            
            self.session.commitConfiguration()
        } catch {
            print("Camera setup error: \(error.localizedDescription)")
        }
    }
}
