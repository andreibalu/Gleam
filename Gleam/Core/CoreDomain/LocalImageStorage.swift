import Foundation
import UIKit

/// Manages local storage of scan images
/// Images are stored locally only and not synced to cloud
actor LocalImageStorage {
    private let fileManager: FileManager
    private let imagesDirectory: URL
    
    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        
        // Store images in Application Support directory
        let baseDirectory: URL
        if let url = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            baseDirectory = url
        } else if let url = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            baseDirectory = url
        } else {
            baseDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        }
        
        self.imagesDirectory = baseDirectory.appendingPathComponent("ScanImages", isDirectory: true)
        
        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: imagesDirectory.path) {
            try? fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    /// Save image data for a history item
    func saveImage(_ imageData: Data, for historyItemId: String) throws {
        let imageURL = imageURL(for: historyItemId)
        let directory = imageURL.deletingLastPathComponent()
        
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
        
        try imageData.write(to: imageURL, options: .atomic)
    }
    
    /// Load image data for a history item
    func loadImage(for historyItemId: String) -> Data? {
        let imageURL = imageURL(for: historyItemId)
        guard fileManager.fileExists(atPath: imageURL.path) else {
            return nil
        }
        return try? Data(contentsOf: imageURL)
    }
    
    /// Delete image for a history item
    func deleteImage(for historyItemId: String) {
        let imageURL = imageURL(for: historyItemId)
        try? fileManager.removeItem(at: imageURL)
    }
    
    private func imageURL(for historyItemId: String) -> URL {
        imagesDirectory.appendingPathComponent("\(historyItemId).jpg", isDirectory: false)
    }
}

