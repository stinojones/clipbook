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
    @Published var previewURL: URL?
    @Published var currentCameraPosition: AVCaptureDevice.Position = .back
    private var isUsingFrontCamera = false
    
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
    
    
    
    
    //MARK: CONSTRUCTOR
    override init() {
        super.init()
        loadClipsOnAppStart()
    }
    
    
    
    // MARK: - Recording Output Handling
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Error during recording: \(error.localizedDescription)")
            return
        }
        
        guard FileManager.default.fileExists(atPath: outputFileURL.path) else {
            print("Error: File does not exist at \(outputFileURL.path).")
            return
        }
        
        // Sort the recorded URLs to maintain order
        recordedURLs.sort { $0.lastPathComponent < $1.lastPathComponent }
        
        self.recordedURLs.append(outputFileURL)
        print("Recorded URLs: \(recordedURLs)")
        
        videoManager.saveVideo(tempURL: outputFileURL) { success, _ in
            if success {
                print("Has Clips in documents directory after saving")
            } else {
                print("Failed to save video to documents directory.")
            }
        }
        clipCount += 1
        
        if recordedURLs.count == 1 {
            self.previewURL = outputFileURL
            return
        }
        
        let assets = recordedURLs.compactMap { AVURLAsset(url: $0) }
        guard !assets.isEmpty else {
            print("Error: No assets to merge.")
            return
        }
        
        self.previewURL = nil
        mergeVideos(assets: assets) { exporter in
            exporter.exportAsynchronously {
                if exporter.status == .failed {
                    print("Merging failed: \(exporter.error?.localizedDescription ?? "Unknown error")")
                } else if let finalURL = exporter.outputURL {
                    DispatchQueue.main.async {
                        self.previewURL = finalURL
                    }
                }
            }
        }
    }
    
    
    //merge videos of urls
    func mergeVideos(assets: [AVURLAsset], completion: @escaping (_ exporter: AVAssetExportSession) -> ()) {
        print("Merging started with \(assets.count) assets.")
        
        // Ensure there are assets to merge
        guard !assets.isEmpty else {
            print("Error: No assets provided for merging.")
            return
        }
        
        // Sort the assets, if needed (e.g., by filename or creation date)
        let sortedAssets = assets.sorted(by: { $0.url.lastPathComponent < $1.url.lastPathComponent })
        
        // Create a composition for the merged video
        let composition = AVMutableComposition()
        var lastTime: CMTime = .zero
        
        // Add video and audio tracks
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: Int32(kCMPersistentTrackID_Invalid)),
              let audioDevice = AVCaptureDevice.default(for: .audio),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: Int32(kCMPersistentTrackID_Invalid)) else {
            print("Error: Unable to add tracks to composition.")
            return
        }
        
        // Append each asset's video and audio tracks to the composition
        for asset in sortedAssets {
            guard let sourceVideoTrack = asset.tracks(withMediaType: .video).first else {
                print("Error: Asset has no video track.")
                continue
            }
            
            do {
                try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: sourceVideoTrack, at: lastTime)
                
                if let sourceAudioTrack = asset.tracks(withMediaType: .audio).first {
                    try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: sourceAudioTrack, at: lastTime)
                }
                
                lastTime = CMTimeAdd(lastTime, asset.duration)
            } catch {
                print("Error inserting time range: \(error.localizedDescription)")
            }
        }
        
        // Define the output file URL in a temporary directory
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Merged-\(UUID().uuidString).mov")
        
        // Create video composition instructions for proper transformations and orientation
        let instructions = AVMutableVideoCompositionInstruction()
        instructions.timeRange = CMTimeRange(start: .zero, duration: lastTime)
        
        let layerInstructions = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        if let firstAsset = sortedAssets.first,
           let firstVideoTrack = firstAsset.tracks(withMediaType: .video).first {
            let preferredTransform = firstVideoTrack.preferredTransform
            layerInstructions.setTransform(preferredTransform, at: .zero)
        }
        instructions.layerInstructions = [layerInstructions]
        
        // Set up the video composition for rendering
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: videoTrack.naturalSize.height, height: videoTrack.naturalSize.width)
        videoComposition.instructions = [instructions]
        videoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)
        
        // Configure the exporter
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            print("Error: Unable to create AVAssetExportSession.")
            return
        }
        exporter.outputFileType = .mov
        exporter.outputURL = tempURL
        exporter.videoComposition = videoComposition
        
        // Return the exporter through the completion handler
        completion(exporter)
    }
    //undo videos of urls
    func undoTempvideo() {
        guard !recordedURLs.isEmpty else {
            print("Error: No videos to undo.")
            return
        }
        
        self.recordedURLs.removeLast()
        print("Updated URLs after undo: \(recordedURLs)")
        
        if recordedURLs.isEmpty {
            previewURL = nil
        } else {
            let assets = recordedURLs.compactMap { AVURLAsset(url: $0) }
            guard !assets.isEmpty else {
                print("Error: No assets available for merging after undo.")
                return
            }
            self.previewURL = nil
            mergeVideos(assets: assets) { exporter in
                exporter.exportAsynchronously {
                    if exporter.status == .failed {
                        print("Merging failed: \(exporter.error?.localizedDescription ?? "Unknown error")")
                    } else if let finalURL = exporter.outputURL {
                        DispatchQueue.main.async {
                            self.previewURL = finalURL
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Recording Functions
    func startRecording() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"  // Format with exact time and milliseconds
        
        // Generate a precise temp URL with the formatted timestamp and .mov extension
        let tempURL = NSTemporaryDirectory() + "video_\(dateFormatter.string(from: Date())).mov"
        output.startRecording(to: URL(fileURLWithPath: tempURL), recordingDelegate: self)
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
        
        // MARK: - Handle App Lifecycle
        if isRecording {
            NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
            NotificationCenter.default.post(name: UIApplication.willTerminateNotification, object: nil)
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
    
    func setUpFrontCamera() {
        if let frontCamera = AVCaptureDevice.default(for: .video) {
            do {
                let frontVideoInput = try AVCaptureDeviceInput(device: frontCamera)

                if session.canAddInput(frontVideoInput) {
                    session.addInput(frontVideoInput)
                    
                    // Setting the zoom factor to minimum (zoomed-out)
                    if frontCamera.isFocusModeSupported(.autoFocus) {
                        try frontCamera.lockForConfiguration()
                        frontCamera.videoZoomFactor = frontCamera.minAvailableVideoZoomFactor
                        frontCamera.unlockForConfiguration()
                    }

                    if session.canAddOutput(output) {
                        session.addOutput(output)
                    }
                }
            } catch {
                print("Error setting up front camera: \(error.localizedDescription)")
            }
        }
    }
    
    func loadClipsOnAppStart() {
        // Get all URLs from the clipsDirectory
        let fileManager = FileManager.default
        if let files = try? fileManager.contentsOfDirectory(at: videoManager.clipsDirectory, includingPropertiesForKeys: nil) {
            let clipAssets = files.compactMap { AVURLAsset(url: $0) }
            
            if !clipAssets.isEmpty {
                // Sort assets by creation date or filename
                let sortedAssets = clipAssets.sorted(by: { $0.url.lastPathComponent < $1.url.lastPathComponent })
                
                self.recordedURLs = sortedAssets.map { $0.url }
                print("Loaded clips: \(recordedURLs)")
                
                self.previewURL = nil
                if sortedAssets.count == 1 {
                    // Directly set previewURL to the single clip
                    self.previewURL = sortedAssets.first?.url
                    print("Single clip preview URL: \(self.previewURL)")
                } else if sortedAssets.count > 1 {
                    // Perform merging if more than one clip exists
                    mergeVideos(assets: sortedAssets) { exporter in
                        exporter.exportAsynchronously {
                            if exporter.status == .failed {
                                print("Merging failed: \(exporter.error?.localizedDescription ?? "Unknown error")")
                            } else if let finalURL = exporter.outputURL {
                                DispatchQueue.main.async {
                                    self.previewURL = finalURL
                                    print("Merged preview URL: \(self.previewURL)")
                                }
                            }
                        }
                    }
                }
            } else {
                print("No clips found in the directory.")
            }
        } else {
            print("Error accessing clips directory.")
        }
    }
    
    func switchCamera() {
        session.beginConfiguration()
        
        // Remove the current input
        guard let currentInput = session.inputs.first else { return }
        session.removeInput(currentInput)
        
        // Get the new camera device (front or back)
        let newCameraPosition: AVCaptureDevice.Position = currentCameraPosition == .back ? .front : .back
        guard let newCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newCameraPosition) else {
            print("Error: No camera found for position \(newCameraPosition)")
            return
        }
        
        do {
            let videoInput = try AVCaptureDeviceInput(device: newCamera)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
                currentCameraPosition = newCameraPosition
            }
        } catch {
            print("Error: Could not create video input for \(newCameraPosition): \(error)")
        }
        
        session.commitConfiguration()
    }
}
    


