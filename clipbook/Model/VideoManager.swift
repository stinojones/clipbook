import Foundation
import AVFoundation

class VideoManager: ObservableObject {
    
    // stores url that is available for preview
    @Published var previewURL: URL?
    
    @Published var hasClips: Bool = false
    
    // directory use now
    private let clipsDirectory: URL
    
    //MARK: - setting up clipDirectory to ClipbookClips subfolder
    init() {
        
        // setups up clipsDirectory and a subfolder of ClipbookClips
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.clipsDirectory = documentsDirectory.appendingPathComponent("ClipbookClips", isDirectory: true)
        
        // creates directory if it doesn't exist
        createClipsDirectory()
//        updateHasClips()
    }
    
    //MARK: - Create the Clips Directory if It Doesn't Exist and initialized in innit
    private func createClipsDirectory() {
        if !FileManager.default.fileExists(atPath: clipsDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: clipsDirectory, withIntermediateDirectories: true, attributes: nil)
                print("Clips directory created at \(clipsDirectory.path)")
            } catch {
                print("Failed to create clips directory: \(error.localizedDescription)")
            }
        }
        updateHasClips()
    }
    
    // MARK: Save a Video to the Clips Directory in Date Form
    func saveVideo(tempURL: URL, completion: @escaping (Bool, URL?) -> Void) {
        // Generate a timestamp string for the file name
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS" // Precise date format
        let timestamp = dateFormatter.string(from: Date())
        
        // Clip renamed with the timestamp and .mov extension for directory
        let clipName = "clip_\(timestamp).mov"
        
        // Clip destination
        let destinationURL = clipsDirectory.appendingPathComponent(clipName)
        
        // Moves clip with clipname to clipsDirectory
        DispatchQueue.global(qos: .background).async {
            do {
                try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                
                // Ensure updates are performed on the main thread
                DispatchQueue.main.async {
                    self.updateHasClips()   // Update the 'hasClips' state
                    self.updatePreviewURL() // Update preview URL
                    
                    // Notify the caller of success with the saved URL
                    completion(true, destinationURL)
                }
            } catch {
                DispatchQueue.main.async {
                    // Notify the caller of failure
                    print("Error saving video: \(error.localizedDescription)")
                    completion(false, nil)
                }
            }
        }
    }
    // MARK: Fetch All Clips from Directory and Merge Them
    func mergeClipsForPreview(completion: @escaping (_ previewURL: URL?) -> ()) {
        // Fetch all video clips from the directory
        guard let clips = getAllClips(), !clips.isEmpty else {
            print("No clips available to merge.")
            completion(nil)
            return
        }
        
        // If there is only one clip, return it directly
        if clips.count == 1 {
            print("Only one clip available, returning it as preview.")
            completion(clips.first)  // Return the URL of the single clip
            return
        }
        
        // Convert the URLs to AVURLAsset objects
        let assets = clips.compactMap { AVURLAsset(url: $0) }
        
        // Call the mergeVideo function to merge the assets into one
        mergeVideo(assets: assets) { exporter in
            exporter.exportAsynchronously {
                if exporter.status == .failed {
                    print(exporter.error?.localizedDescription ?? "Export failed")
                    completion(nil)  // Return nil if the export fails
                } else {
                    if let finalURL = exporter.outputURL {
                        print("Merged video created at: \(finalURL)")
                        DispatchQueue.main.async {
                            // Pass the final merged video URL to the completion handler
                            completion(finalURL)
                        }
                    } else {
                        completion(nil)  // Return nil if no URL is found
                    }
                }
            }
        }
    }
    // MARK: Merge Videos
    func mergeVideo(assets: [AVURLAsset], completion: @escaping (_ exporter: AVAssetExportSession) -> ()) {
        let composition = AVMutableComposition()
        var lastTime: CMTime = .zero
        
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: Int32(kCMPersistentTrackID_Invalid)) else { return }
        guard let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: Int32(kCMPersistentTrackID_Invalid)) else { return }
        
        for asset in assets {
            do {
                // Insert the video and audio from each asset
                try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: asset.tracks(withMediaType: .video)[0], at: lastTime)
                if let audio = asset.tracks(withMediaType: .audio).first {
                    try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: audio, at: lastTime)
                }
            } catch {
                print("Error inserting time range: \(error.localizedDescription)")
            }
            lastTime = CMTimeAdd(lastTime, asset.duration)
        }
        
        // Set up the video composition and instructions
        let layerInstructions = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        
        // MARK: - Rotating Video to be normal
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
        
        // MARK: - Temp Output URL
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mergedVideo_\(Date().timeIntervalSince1970).mp4")
        
        
        
        
        // Set up the export session
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { return }
        exporter.outputFileType = .mp4
        exporter.outputURL = tempURL
        exporter.videoComposition = videoComposition
        
        // Pass the exporter back in the completion handler
        completion(exporter)
    }
    
    // MARK: Get All Clips (Fetch Videos Dynamically from Directory)
    func getAllClips() -> [URL]? {
        do {
            // Get all files in the clips directory
            let fileURLs = try FileManager.default.contentsOfDirectory(at: clipsDirectory, includingPropertiesForKeys: [.creationDateKey])
            
            // Filter out non-video files
            let videoFiles = fileURLs.filter { $0.pathExtension.lowercased() == "mov" }
            
            // Sort the files by filename (date-based naming) or fallback to creation date
            let sortedFiles = videoFiles.sorted {
                // Try to sort by filenames
                if $0.lastPathComponent < $1.lastPathComponent {
                    return true
                } else if $0.lastPathComponent > $1.lastPathComponent {
                    return false
                }
                
                // If filenames are the same or inconsistent, sort by creation date
                let attributes1 = try? FileManager.default.attributesOfItem(atPath: $0.path)
                let attributes2 = try? FileManager.default.attributesOfItem(atPath: $1.path)
                let date1 = attributes1?[.creationDate] as? Date ?? Date.distantPast
                let date2 = attributes2?[.creationDate] as? Date ?? Date.distantPast
                
                return date1 < date2
            }
            
            // Log the sorted order (optional)
            print("Sorted Clips: \(sortedFiles.map { $0.lastPathComponent })")
            
            return sortedFiles
        } catch {
            print("Error fetching clips from directory: \(error.localizedDescription)")
            return nil
        }
    }
    // MARK: Clear All Recorded Files
    func clearRecordedFiles() {
        DispatchQueue.global(qos: .background).async {
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(at: self.clipsDirectory, includingPropertiesForKeys: nil)
                for url in fileURLs {
                    try FileManager.default.removeItem(at: url)
                }
                DispatchQueue.main.async {
                    print("Cleared all recorded files.")
                }
            } catch {
                print("Failed to clear files: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: Get the Clips Directory URL
    func getClipsDirectoryURL() -> URL {
        return clipsDirectory
    }
    
    // MARK: - See if clips inside of directory for preview button to work
    func hasClipsInDirectory() -> Bool {
        let fileManager = FileManager.default
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: clipsDirectory.path)
            return !contents.isEmpty
        } catch {
            print("Error reading directory contents: \(error.localizedDescription)")
            return false
        }
    }
    
    
    
    func updateHasClips() {
        DispatchQueue.global(qos: .background).async {
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(at: self.clipsDirectory, includingPropertiesForKeys: nil)
                
                // Filter for only .mov files, if necessary
                let clipFiles = fileURLs.filter { $0.pathExtension == "mov" }
                
                DispatchQueue.main.async {
                    // Update hasClips only if there are .mov clips
                    self.hasClips = !clipFiles.isEmpty
                }
            } catch {
                // Log the error but continue
                print("Failed to check clips directory: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    // In case of error, reset hasClips to false
                    self.hasClips = false
                }
            }
        }
    }
    // Function to update the preview URL
    func updatePreviewURL() {
        if hasClips {
            // If there's only one clip, set previewURL directly without merging
            if let clips = getAllClips(), clips.count == 1 {
                self.previewURL = clips.first // Directly set the preview URL to the single clip
            } else {
                // Call your preview generation logic here for merging clips
                mergeClipsForPreview { previewURL in
                    if let previewURL = previewURL {
                        self.previewURL = previewURL
                    }
                }
            }
        } else {
            // If no clips are available, reset the preview URL
            self.previewURL = nil
        }
    }
    
    
}
