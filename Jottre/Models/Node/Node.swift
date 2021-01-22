//
//  Node.swift
//  Jottre
//
//  Created by Anton Lorani on 16.01.21.
//

import Foundation
import PencilKit
import os.log


/// A custom helper class that generates the thumbnails for a given Node
var thumbnailGenerator: ThumbnailGenerator = ThumbnailGenerator(size: CGSize(width: UIScreen.main.bounds.width >= (232 * 2 + 40) ? 232 : UIScreen.main.bounds.width - 4, height: 291))


/// The content of this struct will be serialized to a binary file
struct NodeCodable: Codable {
    
    var drawing: PKDrawing = PKDrawing()
    
    var width: CGFloat = 1200
    
}


/// This class will manage the processes of a NodeCodable
/// This includes: encoding, decoding and basic file system related methods
class Node: NSObject {
    
    // MARK: - Properties
    
    var name: String?
    
    var url: URL? {
        didSet {
            guard let url = url else { return }
            name = url.deletingPathExtension().lastPathComponent
        }
    }
    
    var thumbnail: UIImage?
    
    var codable: NodeCodable?
    
    var collector: NodeCollector?
    
    private var serializationQueue = DispatchQueue(label: "NodeSerializationQueue", qos: .background)
    
    
    
    // MARK: - Init
    
    /// Initializer for a Node from a custom url
    /// - Parameter url: Should point to a .jot file on the users file-system
    init(url: URL) {
        super.init()
        
        setupValues(url: url, nodeCodable: NodeCodable())
        
    }
    
    
    /// Helper method for the initializer
    /// - Parameters:
    ///   - url: url passed via initializer
    ///   - nodeCodable: A valid NodeCodable object
    private func setupValues(url: URL, nodeCodable: NodeCodable) {
        self.url = url
        self.codable = nodeCodable
    }
    
    
    
    // MARK: - Methods
    
    /// Loading Node from file
    /// - Parameter completion: Returns a boolean that indicates success or failure
    func pull(completion: ((Bool) -> Void)? = nil) {
        
        serializationQueue.async {
            
            guard let url = self.url, url.isJot() else {
                return
            }
            
            guard FileManager.default.fileExists(atPath: url.path) else {
                Logger.main.debug("File \(url.path) does not exist")
                completion?(false)
                return
            }
            
            do {
                let decoder = PropertyListDecoder()
                let data = try Data(contentsOf: url)
                self.codable = try decoder.decode(NodeCodable.self, from: data)
            } catch {
                Logger.main.error("Could not read node from file: \(url.path)")
                completion?(false)
            }
            
            self.updateMeta()
                        
            completion?(true)
            
        }
        
    }
    
    
    /// Writing Node to file
    /// - Parameter completion: Returns a boolean that indicates success or failure
    func push(completion: ((Bool) -> Void)? = nil) {
        
        serializationQueue.async {
            
            guard let nodeCodable = self.codable, let url = self.url else {
                completion?(false)
                return
            }
            
            do {
                let encoder = PropertyListEncoder()
                let data = try encoder.encode(nodeCodable)
                try data.write(to: url)
            } catch {
                Logger.main.error("Could not write NodeCodable to file: \(error.localizedDescription)")
                completion?(false)
            }
            
            completion?(true)
            
        }
        
    }
    
    
    /// Updates meta-data such as the thumbnail of the Node
    /// - Parameter completion: Returns a boolean that indicates success or failure
    func updateMeta(completion: ((Bool) -> Void)? = nil) {
        
        thumbnailGenerator.execute(for: self) { [self] (success, image) in
            self.thumbnail = image
            
            if let collector = self.collector {
                collector.didUpdate()
            }
            
            completion?(success)
        }
        
    }
    
    
    /// Moves drawing to Node. Calls update to generate thumbnail
    /// - Parameter drawing: Given PKDrawing
    func setDrawing(drawing: PKDrawing) {
        
        codable?.drawing = drawing
        updateMeta()
        
        push()
        
    }
 
    
    
    // MARK: - Filesystem methods
    
    /// Renames the Nodes name
    /// IMPORTANT: - name = name.jot; name.jot = name
    /// - Parameters:
    ///   - name: New name of the Node
    ///   - completion: Returns a boolean that indicates success or failure
    func rename(to name: String, completion: ((Bool) -> Void)? = nil) {
        
        guard let originPath = url, let destinationPath = url?.deletingLastPathComponent().appendingPathComponent(name).appendingPathExtension("jot") else {
            completion?(false)
            return
        }
        
        do {
            try FileManager.default.moveItem(at: originPath, to: destinationPath)
        } catch {
            Logger.main.error("\(error.localizedDescription)")
            completion?(false)
        }
        
        self.name = name
        
        completion?(true)
        
    }
    
    
    /// Clones the Node's content. Name will be updated automatically with suffix 'copy'
    /// - Parameter completion: Returns a boolean that indicates success or failure
    func duplicate(completion: ((Bool) -> Void)? = nil) {
        completion?(false)
    }
    
    
    /// Deletes the Node from the filesystem
    /// - Parameter completion: Returns a boolean that indicates success or failure
    func delete(completion: ((Bool) -> Void)? = nil) {
        
        guard let url = url else {
            completion?(false)
            return
        }
        
        guard let collector = collector, let index = collector.nodes.firstIndex(of: self) else {
            completion?(false)
            return
        }
        
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Logger.main.error("Could not delete Node at \(url). Reason: \(error.localizedDescription)")
            completion?(false)
        }

        collector.nodes.remove(at: index)
        completion?(true)

    }
    
}