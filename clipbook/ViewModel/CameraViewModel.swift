import SwiftUI
import AVFoundation

class CameraViewModel: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    
    // MARK: - Camera Properties
    @Published var session = AVCaptureSession()
    @Published var tempFileURL: URL?
    @Published var alert = false
    @Published var output = AVCaptureMovieFileOutput()
    @Published var preview: AVCaptureVideoPreviewLayer!
    @Published var player: AVPlayer? 
    
    // MARK: - Video Recording States
    @Published var isRecording: Bool = false
    @Published var recordedURLs: [URL] = []
    @Published var showPreview: Bool = false
    
    // MARK: - Progress Bar Properties
    @Published var recordedDuration: CGFloat = 0.00
    @Published var maxDuration: CGFloat = 10.00 
    
    // Video manager initialized
    private let videoManager = VideoManager()
    
    // MARK: - UserDefaults Keys and Stored Data
    private let clipTimesKey = "clipTimes"
    var clipTimes: [CGFloat] {
        get {
            return UserDefaults.standard.array(forKey: clipTimesKey) as? [CGFloat] ?? []
        }
        set {
            UserDefaults.standard.set(newValue, forKey: clipTimesKey)
        }
    }
    
    var clipCount: Int {
        get {
            return UserDefaults.standard.integer(forKey: "clipCount")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "clipCount")
        }
    }
    
    // Progress calculated dynamically
    var progress: CGFloat {
        let totalDuration = clipTimes.reduce(0, +) + recordedDuration
        return min(totalDuration / maxDuration, 1.0)
    }
    
    // MARK: - Recording Output Handling
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Error during recording: \(error.localizedDescription)")
            return
        }
        
        // Save the video to the Clips directory
        videoManager.saveVideo(tempURL: outputFileURL) { success, _ in
            if success {
                print("Has Clips in directory after saving: \(self.videoManager.hasClipsInDirectory())")
            } else {
                print("Failed to save video.")
            }
        }
        clipCount += 1
    }
    
    // MARK: - Recording Functions
    func startRecording() {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tempRecording_\(UUID().uuidString).mov")
        self.tempFileURL = tempURL
        output.startRecording(to: tempURL, recordingDelegate: self)
        isRecording = true
    }
    
    func stopRecording() {
        output.stopRecording()
        isRecording = false
        
        // Append the recorded duration to `clipTimes` in real-time
        if recordedDuration > 0 {
            clipTimes.append(recordedDuration)
            recordedDuration = 0 // Reset for the next recording
            
            // Save updated `clipTimes` to UserDefaults
            UserDefaults.standard.set(clipTimes, forKey: clipTimesKey)
        }
    }
    
    // Undo the last recorded clip
    func undoLastClip() {
        if !clipTimes.isEmpty {
            clipTimes.removeLast()
            recordedDuration = 0
            clipCount -= 1
        }
    }
    
    
    
    // Reset all recorded clips
    func resetAllClips() {
        clipTimes.removeAll()
        recordedDuration = 0
        clipCount = 0
    }
    
    
    // MARK: - Camera Setup
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
    
    func setUp() {
        do {
            self.session.beginConfiguration()
            
            guard let cameraDevice = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) else {
                print("Error: No ultrawide camera found.")
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
