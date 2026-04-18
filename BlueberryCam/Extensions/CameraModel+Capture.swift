import AVFoundation
import CoreImage
import CoreLocation
import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers

extension CameraModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        if let error = error {
            Task { @MainActor in self.errorMessage = error.localizedDescription; self.showError = true }
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            Task { @MainActor in self.errorMessage = "Failed to get photo data."; self.showError = true }
            return
        }
        let isHeif = !photo.isRawPhoto && self._pendingCaptureModeBox.value == .heif
        
        Task {
            let loc = await MainActor.run { self.currentLocation }
            let filteredData = self.filteredPhotoDataIfNeeded(
                from: data,
                isRaw: photo.isRawPhoto,
                isHEIF: isHeif
            ) ?? data
            self.saveToPhotos(data: filteredData, location: loc, isDNG: photo.isRawPhoto, isHEIF: isHeif)
        }
    }
    
    private nonisolated func saveToPhotos(data: Data, location: CLLocation?, isDNG: Bool, isHEIF: Bool = false) {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        
        guard currentStatus == .authorized || currentStatus == .limited else {
            Task { @MainActor in
                self.errorMessage = "Photos access denied. Please enable in Settings."
                self.showError = true
            }
            return
        }
        
        performSave(data: data, location: location, isDNG: isDNG, isHEIF: isHEIF)
    }
    
    private nonisolated func performSave(data: Data, location: CLLocation? = nil, isDNG: Bool, isHEIF: Bool) {
        let readWriteStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let album: PHAssetCollection?
        if readWriteStatus == .authorized || readWriteStatus == .limited {
            let albumID = resolveAlbumID()
            album = albumID.flatMap {
                PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [$0], options: nil).firstObject
            }
        } else {
            album = nil
        }
        
        PHPhotoLibrary.shared().performChanges({
            let opts = PHAssetResourceCreationOptions()
            opts.uniformTypeIdentifier = BundleIDs.UTI(isDNG: isDNG, isHEIF: isHEIF)
            let req = PHAssetCreationRequest.forAsset()
            if let loc = location {
                req.location = loc
            }
            req.addResource(with: .photo, data: data, options: opts)
            
            if let album = album, let placeholder = req.placeholderForCreatedAsset {
                let albumReq = PHAssetCollectionChangeRequest(for: album)
                albumReq?.addAssets([placeholder] as NSArray)
            }
        }) { success, error in
            Task { @MainActor in
                if !success {
                    self.errorMessage = error?.localizedDescription ?? "Unknown save error."
                    self.showError = true
                }
            }
        }
    }
    
    private nonisolated func filteredPhotoDataIfNeeded(from data: Data,
                                                       isRaw: Bool,
                                                       isHEIF: Bool) -> Data? {
        guard !isRaw else { return data }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let sourceType = CGImageSourceGetType(source),
              let sourceImage = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            return nil
        }
        
        let filteredImage = sourceImage
        
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let context = CIContext()
        guard let cgImage = context.createCGImage(filteredImage, from: filteredImage.extent, format: .RGBX8, colorSpace: colorSpace) else {
            return nil
        }
        
        let metadata = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        var outputMetadata = metadata
        outputMetadata[kCGImagePropertyOrientation] = CGImagePropertyOrientation.up.rawValue
        
        let destinationUTType: CFString = isHEIF ? (UTType.heic.identifier as CFString) : sourceType
        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(outputData, destinationUTType, 1, nil) else {
            return nil
        }
        
        CGImageDestinationAddImage(destination, cgImage, outputMetadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        
        return outputData as Data
    }
    
    private nonisolated func processedImage(named filterName: String,
                                            inputImage: CIImage,
                                            parameters: [String: Any] = [:]) -> CIImage? {
        guard let filter = CIFilter(name: filterName) else { return nil }
        filter.setValue(inputImage, forKey: kCIInputImageKey)
        for (key, value) in parameters {
            filter.setValue(value, forKey: key)
        }
        return filter.outputImage
    }
    
    private nonisolated func croppedImage(_ image: CIImage, to extent: CGRect) -> CIImage {
        image.cropped(to: extent)
    }
    
    private nonisolated func largestInscribedSquareBySampling(_ image: CIImage, threshold: CGFloat = 0.01) -> CGRect {
        let extent = image.extent.integral
        let sampleSize = CGSize(width: 256, height: max(1, Int((256.0 / extent.width) * extent.height)))
        let scaleX = sampleSize.width / extent.width
        let scaleY = CGFloat(sampleSize.height) / extent.height
        
        let resized = image.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let width = Int(sampleSize.width)
        let height = Int(sampleSize.height)
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        guard let cg = context.createCGImage(resized, from: CGRect(x: 0, y: 0, width: sampleSize.width, height: CGFloat(height))) else {
            return extent
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapCtx = CGContext(data: &rgba, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        bitmapCtx?.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        func alphaAt(_ x: Int, _ y: Int) -> CGFloat {
            let idx = (y * width + x) * 4 + 3
            return CGFloat(rgba[idx]) / 255.0
        }
        
        let midX = width / 2
        let midY = height / 2
        
        var left = 0
        while left < midX && alphaAt(left, midY) < threshold { left += 1 }
        var right = width - 1
        while right > midX && alphaAt(right, midY) < threshold { right -= 1 }
        var bottom = 0
        while bottom < midY && alphaAt(midX, bottom) < threshold { bottom += 1 }
        var top = height - 1
        while top > midY && alphaAt(midX, top) < threshold { top -= 1 }
        
        let leftF = CGFloat(left) / scaleX
        let rightF = CGFloat(right) / scaleX
        let bottomF = CGFloat(bottom) / scaleY
        let topF = CGFloat(top) / scaleY
        
        let contentMinX = max(extent.minX, extent.minX + leftF)
        let contentMaxX = min(extent.maxX, extent.minX + rightF)
        let contentMinY = max(extent.minY, extent.minY + bottomF)
        let contentMaxY = min(extent.maxY, extent.minY + topF)
        
        let contentWidth = max(0, contentMaxX - contentMinX)
        let contentHeight = max(0, contentMaxY - contentMinY)
        
        let side = min(contentWidth, contentHeight)
        let centerX = (contentMinX + contentMaxX) * 0.5
        let square = CGRect(x: -centerX, y: 2 * centerX, width: side, height: side)
        
        return square.integral
    }
}
