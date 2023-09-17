//
// ExportActions.swift
// Jottre
//
// Created by Anton Lorani on 16.01.21.
//

import UIKit
import OSLog

extension DrawViewController {
    // Add UploadIOError enum
    enum UploadIOError: Error {
        case invalidURL
        case invalidRequestBody
        case invalidResponseData
        case noFileURLInResponse
        case failedToUploadImage
        
        var localizedDescription: String {
            switch self {
            case .invalidURL:
                return "Invalid URL."
            case .invalidRequestBody:
                return "Invalid request body."
            case .invalidResponseData:
                return "Invalid response data."
            case .noFileURLInResponse:
                return "No file URL found in the response."
            case .failedToUploadImage:
                return "Failed to upload the image."
            }
        }
    }
    
    enum APIError: Error {
        case invalidURL
        case invalidRequestBody
        case invalidResponseData
        case processingFailed
        case invalidImageData
    }
    
    // Add uploadImageToUploadIO function
    func uploadImageToUploadIO(imageData: Data, completion: @escaping (Result<String, UploadIOError>) -> Void) {
        guard let url = URL(string: "https://api.upload.io/v2/accounts/W142hnL/uploads/binary") else {
            completion(.failure(.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer public_W142hnL6wgfrhUY3zqTgexjTxCtM", forHTTPHeaderField: "Authorization")
        request.addValue("image/png", forHTTPHeaderField: "Content-Type")
        request.httpBody = imageData
        
        let session = URLSession.shared
        let task = session.dataTask(with: request) { (data, response, error) in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error: \(error.localizedDescription)")
                    completion(.failure(.failedToUploadImage))
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    print("Status code: \(httpResponse.statusCode)")
                }
                
                if let data = data {
                    print("Response data: \(String(data: data, encoding: .utf8) ?? "No data")")
                }
                
                // Update the JSON handling
                guard let data = data, let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any], let fileUrl = json["fileUrl"] as? String else {
                    completion(.failure(.failedToUploadImage))
                    return
                }
                
                completion(.success(fileUrl))
            }
        }
        task.resume()
    }
    
    func sendDrawingToReplicateAPI(imageUrl: String, completion: @escaping (Result<String, Error>) -> Void) {
        let replicateApiKey = "19b22a9cc72c8a00c18c6b0b594832c20312aed9"
        
        guard let url = URL(string: "https://api.replicate.com/v1/predictions") else {
            completion(.failure(APIError.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Token \(replicateApiKey)", forHTTPHeaderField: "Authorization")
        
        let input = [
            "image": imageUrl,
            "prompt": "sleek product design, minimalistic product render, 8k, low noise, octane render, minimal design, product design, Fully rendered product design blender 8K ultra high resolution, photorealistic, octane render design image, metal smooth surface, tech Color Palette, Low saturation color, Subtle design details, super smooth, flawless, clean background",
            "structure": "normal",
            "num_samples": "1",
            "image_resolution": "768",
            "steps": 20,
            "scale": 9,
            "eta": 0,
            "a_prompt": "best quality, extremely detailed",
            "n_prompt": "longbody, lowres, bad anatomy, bad hands, missing fingers, extra digit, fewer digits, cropped, worst quality, low quality",
            //"detect_resolution": 512,
            //"bg_threshold": 0,
        ] as [String : Any]
        
        let body =
        [
            "version": "65169211604c2b950fc4a29541e8ef401c5aed3ecb139e03f3afafb8a75ddb54",
            "input": input
        ] as [String: Any]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            completion(.failure(APIError.invalidRequestBody))
            return
        }
        
        request.httpBody = httpBody
        
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            if let error = error {
                print("Error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let data = data, let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                print("Invalid response data: \(String(data: data ?? Data(), encoding: .utf8) ?? "No data")")
                completion(.failure(APIError.invalidResponseData))
                return
            }
            
            print("JSON response: \(json)")
            
            guard let urls = json["urls"] as? [String: Any], let getUrl = urls["get"] as? String else {
                print("Failed to get URL: \(json)") // Add this line to print the JSON when failing to get the URL
                completion(.failure(APIError.processingFailed))
                return
            }
            
            print("Get URL: \(getUrl)")
            self.pollReplicateAPI(url: getUrl, completion: completion) // Add this line to start polling
        }
        
        task.resume()
    }
    
    func pollReplicateAPI(url: String, completion: @escaping (Result<String, Error>) -> Void) {
        var request = URLRequest(url: URL(string: url)!)
        request.setValue("Token 19b22a9cc72c8a00c18c6b0b594832c20312aed9", forHTTPHeaderField: "Authorization") // Add this line to set the API token in the header
        
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data, let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                completion(.failure(APIError.invalidResponseData))
                return
            }
            
            print("Polling JSON response: \(json)")
            
            if let status = json["status"] as? String, status == "succeeded" {
                guard let output = json["output"] as? [String], output.count >= 1 else {
                    completion(.failure(APIError.processingFailed))
                    return
                }
                
                let imageUrl = output[0] // This corresponds to the second URL in the output array
                completion(.success(imageUrl))
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.pollReplicateAPI(url: url, completion: completion)
                }
            }
        }
        
        task.resume()
    }
    
    func downloadImage(from url: String, completion: @escaping (Result<UIImage, Error>) -> Void) {
        guard let imageURL = URL(string: url) else {
            completion(.failure(APIError.invalidURL))
            return
        }
        
        URLSession.shared.dataTask(with: imageURL) { (data, response, error) in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data, let image = UIImage(data: data) else {
                completion(.failure(APIError.invalidImageData))
                return
            }
            
            completion(.success(image))
        }.resume()
    }

    
    func createExportToPDFAction() -> UIAlertAction {
        return UIAlertAction(title: "PDF", style: .default, handler: { (action) in
            self.startLoading()
            
            self.drawingToPDF { (data, _, _) in
                
                guard let data = data else {
                    self.stopLoading()
                    return
                }
                
                let fileURL = Settings.tmpDirectory.appendingPathComponent(self.node.name!).appendingPathExtension("pdf")
                
                if !data.writeToReturingBoolean(url: fileURL) {
                    self.stopLoading()
                    return
                }
                
                let activityViewController = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
                
                DispatchQueue.main.async {
                    self.stopLoading()
                    self.presentActivityViewController(activityViewController: activityViewController)
                }
                
            }
            
        })
    }
    
    func createExportToPNGGAction() -> UIAlertAction {
        return UIAlertAction(title: "PNG", style: .default, handler: { (action) in
            self.startLoading()

            guard let drawing = self.node.codable?.drawing else {
                self.stopLoading()
                return
            }
            
            var bounds = drawing.bounds
                //bounds.size.height = drawing.bounds.maxY
            
            guard let data = drawing.image(from: bounds, scale: 1, userInterfaceStyle: .light).jpegData(compressionQuality: 1) else {
                self.stopLoading()
                return
            }
            
            let fileURL = Settings.tmpDirectory.appendingPathComponent(self.node.name!).appendingPathExtension("png")
            
            if !data.writeToReturingBoolean(url: fileURL) {
                self.stopLoading()
                return
            }
            
            let activityViewController = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            
            DispatchQueue.main.async {
                self.stopLoading()
                self.presentActivityViewController(activityViewController: activityViewController)
            }
        
        })
    }
    
    func createExportToPNGAction() -> UIAlertAction {
        return UIAlertAction(title: "Render", style: .default, handler: { (action) in
            self.startLoading()
            
            guard let drawing = self.node.codable?.drawing else {
                self.stopLoading()
                return
            }
            
            var bounds = drawing.bounds
            let maxDimension = max(bounds.size.height, bounds.size.width)
            bounds.size.height = maxDimension
            bounds.size.width = maxDimension
            //bounds.size.height = drawing.bounds.maxY
            //bounds.size.width = drawing.bounds.maxX
            
            guard let data = drawing.image(from: bounds, scale: 1, userInterfaceStyle: .light).jpegData(compressionQuality: 1) else {
                self.stopLoading()
                return
            }
            
            // Upload image to Upload.io
            self.uploadImageToUploadIO(imageData: data) { result in
                switch result {
                case .success(let imageUrl):
                    // Call Replicate API with the image URL
                    self.sendDrawingToReplicateAPI(imageUrl: imageUrl) { result in
                        DispatchQueue.main.async {
                            self.stopLoading()
                            switch result {
                            case .success(let refinedImageUrl):
                                self.downloadImage(from: refinedImageUrl) { result in
                                    DispatchQueue.main.async {
                                        switch result {
                                        case .success(let image):
                                            let activityViewController = UIActivityViewController(activityItems: [image], applicationActivities: nil)
                                            self.presentActivityViewController(activityViewController: activityViewController)
                                        case .failure(let error):
                                            print("Error downloading image: \(error)")
                                        }
                                    }
                                }
                            case .failure(let error):
                                let alert = UIAlertController(title: "Error", message: "Failed to process the image: \(error.localizedDescription)", preferredStyle: .alert)
                                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                                self.present(alert, animated: true, completion: nil)
                            }
                        }
                    }
                    
                case .failure(let error):
                    DispatchQueue.main.async {
                        self.stopLoading()
                        let alert = UIAlertController(title: "Error", message: "Failed to upload the image: \(error.localizedDescription)", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                        self.present(alert, animated: true, completion: nil)
                    }
                }
            }
        })
    }
    
    func createExportToJPGAction() -> UIAlertAction {
        return UIAlertAction(title: "JPG", style: .default, handler: { (action) in
            self.startLoading()
            
            guard let drawing = self.node.codable?.drawing else {
                self.stopLoading()
                return
            }
            
            var bounds = drawing.bounds
            bounds.size.height = drawing.bounds.maxY + 100
            
            guard let data = drawing.image(from: bounds, scale: 1, userInterfaceStyle: .light).jpegData(compressionQuality: 1) else {
                self.stopLoading()
                return
            }
            
            let fileURL = Settings.tmpDirectory.appendingPathComponent(self.node.name!).appendingPathExtension("jpg")
            
            if !data.writeToReturingBoolean(url: fileURL) {
                self.stopLoading()
                return
            }
            
            let activityViewController = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            
            DispatchQueue.main.async {
                self.stopLoading()
                self.presentActivityViewController(activityViewController: activityViewController)
            }
            
        })
    }
    func createShareAction() -> UIAlertAction {
        return UIAlertAction(title: NSLocalizedString("Share", comment: ""), style: .default, handler: { (action) in
            self.startLoading()
            self.node.push()
            
            guard let url = self.node.url else {
                self.stopLoading()
                return
            }
            
            let activityViewController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            
            DispatchQueue.main.async {
                self.stopLoading()
                self.presentActivityViewController(activityViewController: activityViewController)
            }
            
        })
    }
    
    fileprivate func presentActivityViewController(activityViewController: UIActivityViewController, animated: Bool = true) {
        if let popoverController = activityViewController.popoverPresentationController {
            popoverController.barButtonItem = navigationItem.rightBarButtonItem
        }
        self.present(activityViewController, animated: animated, completion: nil)
    }
    
}

