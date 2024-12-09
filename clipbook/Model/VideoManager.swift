import Foundation
import AVFoundation

class VideoManager: ObservableObject {
    
    @Published var previewURL: URL?
    
    @Published var hasClips: Bool = false
    
    private let clipsDirectory: URL
    
    init() {
        
        // setups up clipsDirectory and a subfolder of ClipbookClips
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.clipsDirectory = documentsDirectory.appendingPathComponent("ClipbookClips", isDirectory: true)
        
        // creates directory if it doesn't exist
        createClipsDirectory()
        // needed for reboot to see preview button with clips in
        updateHasClips()
    }

    
    // Create the Clips Directory if It Doesn't Exist and initialized in innit
    private func createClipsDirectory() {
        if !FileManager.default.fileExists(atPath: clipsDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: clipsDirectory, withIntermediateDirectories: true, attributes: nil)
                print("Clips directory created at \(clipsDirectory.path)")
            } catch {
                print("Failed to create clips directory: \(error.localizedDescription)")
            }
        }
    }
    
    
    // Save a Video to the Clips Directory in Date Form
    func saveVideo(tempURL: URL, completion: @escaping (Bool, URL?) -> Void) {
        // Generate a timestamp string for the file name
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
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
                    // Update the clips and then fetch them
                    self.updateHasClips()   // Update the 'hasClips' state first
                    
                    // Add a small delay to ensure the state has been updated
                    DispatchQueue.main.asyncAfter(deadline: .now()) {
                        // Fetch all clips after hasClips is updated
                        let clips = self.getAllClips()
                        print("Fetched clips after saving: \(clips?.count ?? 0)")
                        print("has clips after save: \(self.hasClips)")

                        // Notify the caller of success with the saved URL
                        completion(true, destinationURL)
                    }
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
    
    
    // Fetch All Clips from Directory and Merge Them
    func mergeClipsForPreview(completion: @escaping (_ previewURL: URL?) -> ()) {
        // Check if clips are available
        guard hasClips else {
            print("No clips available to merge.")
            DispatchQueue.main.async {
                completion(nil)
            }
            return
        }
        
        // Fetch all video clips from the directory
        guard let clips = getAllClips(), !clips.isEmpty else {
            print("No clips available to merge.")
            DispatchQueue.main.async {
                completion(nil)
            }
            return
        }

        // If there is only one clip, return it directly
        if clips.count == 1 {
            hasClips = true
            print("Only one clip available, returning it as preview.")
            DispatchQueue.main.async {
                completion(clips.first)
            }
            return
        }

        // Convert the URLs to AVURLAsset objects
        let assets = clips.compactMap { AVURLAsset(url: $0) }

        // Call the mergeVideo function to merge the assets into one
        mergeVideo(assets: assets) { exporter in
            exporter.exportAsynchronously {
                if exporter.status == .failed {
                    print(exporter.error?.localizedDescription ?? "Export failed")
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                } else {
                    if let finalURL = exporter.outputURL {
                        print("Merged video created at: \(finalURL)")
                        DispatchQueue.main.async {
                            completion(finalURL)
                        }
                    } else {
                        DispatchQueue.main.async {
                            completion(nil)
                        }
                    }
                }
            }
        }
    }
    
    
    // Merge Videos
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
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mergedVideo_\(Date().timeIntervalSince1970).mov")
        
        
        
        
        // Set up the export session
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { return }
        exporter.outputFileType = .mov
        exporter.outputURL = tempURL
        exporter.videoComposition = videoComposition
        
        // Pass the exporter back in the completion handler
        completion(exporter)
    }
    
    
    // Get All Clips (Fetch Videos Dynamically from Directory)
    func getAllClips() -> [URL]? {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: clipsDirectory, includingPropertiesForKeys: [.creationDateKey])
            let videoFiles = fileURLs.filter { $0.pathExtension.lowercased() == "mov" }
            let sortedFiles = videoFiles.sorted {
                if $0.lastPathComponent < $1.lastPathComponent {
                    return true
                } else if $0.lastPathComponent > $1.lastPathComponent {
                    return false
                }
                let attributes1 = try? FileManager.default.attributesOfItem(atPath: $0.path)
                let attributes2 = try? FileManager.default.attributesOfItem(atPath: $1.path)
                let date1 = attributes1?[.creationDate] as? Date ?? Date.distantPast
                let date2 = attributes2?[.creationDate] as? Date ?? Date.distantPast
                return date1 < date2
            }
            
            return sortedFiles
        } catch {
            print("Error fetching clips from directory: \(error.localizedDescription)")
            return nil
        }
    }
    
    
    // Clear All Recorded Files
    func clearRecordedFiles() {
        DispatchQueue.global(qos: .background).async {
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(at: self.clipsDirectory, includingPropertiesForKeys: nil)
                if fileURLs.isEmpty {
                    DispatchQueue.main.async {
                        print("No files to clear.")
                        self.updateHasClips()
                    }
                    return
                }
                
                for url in fileURLs {
                    try FileManager.default.removeItem(at: url)
                }
                
                DispatchQueue.main.async {
                    print("Cleared all recorded files.")
                    self.updateHasClips()
                }
            } catch {
                print("Failed to clear files: \(error.localizedDescription)")
            }
        }
    }
    
    
    // Get the Clips Directory URL
    func getClipsDirectoryURL() -> URL {
        return clipsDirectory
    }
    
    
    // See if clips inside of directory for preview button to work
    func hasClipsInDirectory() -> Bool {
        let fileManager = FileManager.default
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: clipsDirectory.path)
            
            // needed to check directory and preview button to work
            updateHasClips()
            
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
                
                // Filter for only .mov files, you could extend this to support other formats
                let clipFiles = fileURLs.filter { $0.pathExtension.lowercased() == "mov" }
                
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
}
