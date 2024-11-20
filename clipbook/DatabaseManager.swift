// here's my new database that runs with the console and the clips are insertered succesfully
//I'll take a video now once it fully loads
//heres the console
// takin a video now
// another
//both saved successfully!!!!

// provides core functionalities
import Foundation

// provides library for SQLite databaes
import SQLite3


class DatabaseManager: ObservableObject {
    
    // @Published is a wrapper that updates quickly on any changes made with clips and those changes will still show on other files using Database
    @Published var clips: [(fileURL: URL, timestamp: String)] = []
    var db: OpaquePointer?
    
    init() {
        // Initialize the database
        let fileURL = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("clipsDatabase.sqlite")
        
        if sqlite3_open(fileURL.path, &db) != SQLITE_OK {
            print("Error opening database")
        }
        
        // Create table if it doesn't exist
        let createTableQuery = """
        CREATE TABLE IF NOT EXISTS clips (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            fileName TEXT,
            timestamp TEXT
        );
        """
        
        if sqlite3_exec(db, createTableQuery, nil, nil, nil) != SQLITE_OK {
            print("Error creating table")
        }
    }
    
    // Insert a clip into the database
    func insertClip(fileURL: String) {
        let insertQuery = "INSERT INTO clips (fileName, timestamp) VALUES (?, ?);"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, insertQuery, -1, &statement, nil) == SQLITE_OK {
            // Bind fileURL
            sqlite3_bind_text(statement, 1, fileURL, -1, nil)
            
            // Format the date to a standard format before binding it
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MM-dd-yyyy hh:mm a"  // Example format: "11-11-2024 03:23 PM"
            let timestamp = dateFormatter.string(from: Date())
            
            // Bind timestamp
            sqlite3_bind_text(statement, 2, timestamp, -1, nil)
            
            if sqlite3_step(statement) == SQLITE_DONE {
                print("Successfully inserted clip")
            } else {
                print("Failed to insert clip")
            }
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("Failed to prepare insert statement. Error: \(errorMessage)")
        }
        
        sqlite3_finalize(statement)
    }
    
    
    
    // Fetch all clips from the database and update the clips property
    func fetchClips() {
        let fetchQuery = "SELECT * FROM clips;"
        var statement: OpaquePointer?
        var fetchedClips: [(fileURL: URL, timestamp: String)] = []
        
        if sqlite3_prepare_v2(db, fetchQuery, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let fileURLCString = sqlite3_column_text(statement, 1) {
                    let fileURLString = String(cString: fileURLCString)
                    let timestamp = String(cString: sqlite3_column_text(statement, 2))
                    
                    if let fileURL = URL(string: fileURLString) {
                        fetchedClips.append((fileURL: fileURL, timestamp: timestamp))
                    }
                }
            }
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("Failed to fetch clips. Error: \(errorMessage)")
        }
        
        sqlite3_finalize(statement)
        
        // Update the published clips property
        DispatchQueue.main.async {
            self.clips = fetchedClips
        }
    }
    
    // Close the database connection when the class instance is deallocated
    deinit {
        sqlite3_close(db)
    }
}
