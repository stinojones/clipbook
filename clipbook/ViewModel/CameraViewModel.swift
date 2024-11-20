import SwiftUI
import AVFoundation

class CameraViewModel: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    @Published var session = AVCaptureSession()
    @Published var alert = false
    @Published var output = AVCaptureMovieFileOutput()
    @Published var preview: AVCaptureVideoPreviewLayer!
    
//    Observed Object so this class pays attention to any changes made with @Published Database, it will rerender those changes quickly
    @ObservedObject var databaseManager = DatabaseManager()
    
    
    // Other properties and methods...
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print(error.localizedDescription)
            return
        }
        
        // Convert URL to String
        let fileURLString = outputFileURL.absoluteString // or outputFileURL.path
        
        // Create a filename based on the current date and time
        let fileName = "Clip-\(Date().timeIntervalSince1970).mov"
        
        // Insert the file into the database
        databaseManager.insertClip(fileURL: fileURLString)
        
        // Fetch and print all clips to check if the insert worked
        databaseManager.fetchClips()
        
        // Handle video merging and other logic...
        
        // Created successfully
        print(outputFileURL)
        self.recordedURLs.append(outputFileURL)
        
        if self.recordedURLs.count == 1 {
            self.previewURL = outputFileURL
            return
        }
        
        // Converting URLs to assets
        let assets = recordedURLs.compactMap { url -> AVURLAsset in
            return AVURLAsset(url: url)
        }
        
        self.previewURL = nil
        
        // Merging videos
        mergeVideo(assets: assets) { exporter in
            exporter.exportAsynchronously {
                if exporter.status == .failed {
                    // Handle error
                    print(exporter.error!)
                } else {
                    if let finalURL = exporter.outputURL {
                        print(finalURL)
                        DispatchQueue.main.async {
                            self.previewURL = finalURL
                        }
                    }
                }
            }
        }
    }
    
    // MARK: Video Recorder Properties
    @Published var isRecording: Bool = false
    @Published var recordedURLs: [URL] = []
    @Published var previewURL: URL?
    @Published var showPreview: Bool = false
    
    // Top Progress Bar
    @Published var recordedDuration: CGFloat = 0
    //MARK: \/ !!! THE TIMING OF HOW LONG YOU WANT THE VIDEO TO BE !!! \/
    @Published var maxDuration: CGFloat = 10
    
    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setUp()
            return
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { (status) in
                if status {
                    self.setUp()
                }
            }
        case .denied:
            self.alert.toggle()
            return
        default:
            return
        }
    }
    
    func setUp() {
        do {
            self.session.beginConfiguration()
            
            //MARK: \/ !!! CAMERA SETTINGS .builtInTripleCamera MAKES IT 0.5 LENSE AYOOOOOOO !!! \/
            let cameraDevice = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
            let videoInput = try AVCaptureDeviceInput(device: cameraDevice!)
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
            print(error.localizedDescription)
        }
    }
    
    func startRecording() {
        //MARK: Temporary URL for recording Video
        let tempURL = NSTemporaryDirectory() + "\(Date()).mov"
        output.startRecording(to: URL(fileURLWithPath: tempURL), recordingDelegate: self)
        isRecording = true
    }
    
    func stopRecording() {
        output.stopRecording()
        isRecording = false
    }
    
    func mergeVideo(assets: [AVURLAsset], completion: @escaping (_ exporter: AVAssetExportSession) -> ()) {
        let composition = AVMutableComposition()
        var lastTime: CMTime = .zero
        
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: Int32(kCMPersistentTrackID_Invalid)),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: Int32(kCMPersistentTrackID_Invalid)) else { return }
        
        for asset in assets {
            do {
                try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: asset.tracks(withMediaType: .video)[0], at: lastTime)
                if !asset.tracks(withMediaType: .audio).isEmpty {
                    try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: asset.tracks(withMediaType: .audio)[0], at: lastTime)
                }
            } catch {
                print(error.localizedDescription)
            }
            lastTime = CMTimeAdd(lastTime, asset.duration)
        }
        
        // Getting the Documents directory path for a permanent save location
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let finalURL = documentsPath.appendingPathComponent("MergedClip.mp4")
        
        // Delete any existing file at the final URL
        if FileManager.default.fileExists(atPath: finalURL.path) {
            try? FileManager.default.removeItem(at: finalURL)
        }
        
        let layerInstructions = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        var transform = CGAffineTransform.identity
        transform = transform.rotated(by: 90 * (.pi / 180))
        transform = transform.translatedBy(x: 0, y: -videoTrack.naturalSize.height)
        layerInstructions.setTransform(transform, at: .zero)
        
        let instructions = AVMutableVideoCompositionInstruction()
        instructions.timeRange = CMTimeRange(start: .zero, duration: lastTime)
        instructions.layerInstructions = [layerInstructions]
        
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: videoTrack.naturalSize.height, height: videoTrack.naturalSize.width)
        videoComposition.instructions = [instructions]
        videoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)
        
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { return }
        exporter.outputFileType = .mp4
        exporter.outputURL = finalURL
        exporter.videoComposition = videoComposition
        
        // Start the export process
        exporter.exportAsynchronously {
            if exporter.status == .failed {
                print("Merge failed: \(exporter.error!)")
            } else {
                if let finalURL = exporter.outputURL {
                    print("Saved at: \(finalURL)")
                    
                    // Insert the final merged video URL into the database
                    self.databaseManager.insertClip(fileURL: finalURL.absoluteString)
                    
                    DispatchQueue.main.async {
                        self.previewURL = finalURL
                    }
                }
            }
        }
    }



    
//    MARK: Old mergeVideo Setup
    
//    func mergeVideo(assets: [AVURLAsset], completion: @escaping (_ exporter: AVAssetExportSession) -> ()) {
//        let composition = AVMutableComposition()
//        var lastTime: CMTime = .zero
//        
//        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: Int32(kCMPersistentTrackID_Invalid)) else { return }
//        guard let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: Int32(kCMPersistentTrackID_Invalid)) else { return }
//        
//        for asset in assets {
//            // Linking Audio and Video
//            do {
//                try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: asset.tracks(withMediaType: .video)[0], at: lastTime)
//                // Safe check if Video has Audio
//                if !asset.tracks(withMediaType: .audio).isEmpty {
//                    try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: asset.tracks(withMediaType: .audio)[0], at: lastTime)
//                }
//            } catch {
//                // Handle error
//                print(error.localizedDescription)
//            }
//            
//            // Updating last time
//            lastTime = CMTimeAdd(lastTime, asset.duration)
//        }
//        
//        //MARK: Temp Output URL
//        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory() + "Clip-\(Date()).mp4")
//        
//        // Video be rotated, bring it back to regular
//        let layerInstructions = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
//        
//        //MARK: Transform
//        var transform = CGAffineTransform.identity
//        transform = transform.rotated(by: 90 * (.pi / 180))
//        transform = transform.translatedBy(x: 0, y: -videoTrack.naturalSize.height)
//        layerInstructions.setTransform(transform, at: .zero)
//        
//        let instructions = AVMutableVideoCompositionInstruction()
//        instructions.timeRange = CMTimeRange(start: .zero, duration: lastTime)
//        instructions.layerInstructions = [layerInstructions]
//        
//        let videoComposition = AVMutableVideoComposition()
//        videoComposition.renderSize = CGSize(width: videoTrack.naturalSize.height, height: videoTrack.naturalSize.width)
//        videoComposition.instructions = [instructions]
//        videoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)
//        
//        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { return }
//        exporter.outputFileType = .mp4
//        exporter.outputURL = tempURL
//        exporter.videoComposition = videoComposition
//        completion(exporter)
//    }
}
