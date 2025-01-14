import Foundation
import AVFoundation

class VideoManager: ObservableObject {
    
    let clipsDirectory: URL
    
    init() {
        
        // setups up clipsDirectory and a subfolder of ClipbookClips
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.clipsDirectory = documentsDirectory.appendingPathComponent("ClipbookClips", isDirectory: true)
        
        // creates directory if it doesn't exist
        createClipsDirectory()
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
                try FileManager.default.copyItem(at: tempURL, to: destinationURL)

                // Ensure updates are performed on the main thread
                DispatchQueue.main.async {
                    // Update the clips and then fetch them
                    
                    // Add a small delay to ensure the state has been updated
                    DispatchQueue.main.asyncAfter(deadline: .now()) {
                        // Fetch all clips after hasClips is updated
                        let clips = self.getAllClips()
                        print("Fetched clips after saving: \(clips?.count ?? 0)")

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
    func resetAllClips() {
        DispatchQueue.global(qos: .background).async {
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(at: self.clipsDirectory, includingPropertiesForKeys: nil)
                if fileURLs.isEmpty {
                    DispatchQueue.main.async {
                        print("No files to clear.")
                    }
                    return
                }
                
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
    
    // Undo Function: Removes the Last Clip from the Directory
    func undoLastClip() {
        // Fetch all clips from the directory
        guard let clips = getAllClips(), !clips.isEmpty else {
            print("No clips to undo.")
            return
        }
        
        // Get the last clip in the list
        let lastClip = clips.last
        
        // Remove the last clip from the directory
        do {
            if let lastClip = lastClip {
                try FileManager.default.removeItem(at: lastClip)
                print("Successfully removed clip: \(lastClip.path)")
            }
        } catch {
            print("Error removing last clip: \(error.localizedDescription)")
        }
    }
}
