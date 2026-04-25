internal import AVFoundation
import CoreImage
import Foundation
import ImageIO
internal import Photos
import UniformTypeIdentifiers

extension CameraModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        if let error {
            self._burstCaptureTracker.completeCapture(uniqueID: photo.resolvedSettings.uniqueID, success: false)
            Task { @MainActor in self.errorMessage = error.localizedDescription; self.showError = true }
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            self._burstCaptureTracker.completeCapture(uniqueID: photo.resolvedSettings.uniqueID, success: false)
            Task { @MainActor in self.errorMessage = "Failed to get photo data."; self.showError = true }
            return
        }
        let isHeif = !photo.isRawPhoto && self._pendingCaptureModeBox.value == .heif
        let photoFilter = self._pendingPhotoFilterBox.value
        Task {
            let loc = await MainActor.run { self.currentLocation }
            let filteredData = self.filteredPhotoDataIfNeeded(
                from: data,
                filter: photoFilter,
                isRaw: photo.isRawPhoto,
                isHEIF: isHeif
            ) ?? data
            self.saveToPhotos(data: filteredData, location: loc, isDNG: photo.isRawPhoto, isHEIF: isHeif)
            self._burstCaptureTracker.completeCapture(uniqueID: photo.resolvedSettings.uniqueID, success: true)
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
        // Only resolve the album if the user has read/write access.
        // With add-only access, resolveAlbumID() would silently fail.
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
            
            if let album, let placeholder = req.placeholderForCreatedAsset {
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
                                                       filter: PhotoFilter,
                                                       isRaw: Bool,
                                                       isHEIF: Bool) -> Data? {
        guard !isRaw, filter != .off else { return data }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let sourceType = CGImageSourceGetType(source),
              let sourceImage = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            return nil
        }
        
        let filteredImage: CIImage
        
        switch filter {
            case .off:
                filteredImage = sourceImage
            case .temperatureAndTint:
                guard let output = processedImage(
                    named: "CITemperatureAndTint",
                    inputImage: sourceImage,
                    parameters: [
                        "inputNeutral": CIVector(x: 11500, y: 16),
                        "inputTargetNeutral": CIVector(x: 5000, y: 0)
                    ]
                ) else { return nil }
                filteredImage = croppedImage(output, to: sourceImage.extent)
            case .chrome:
                guard let output = processedImage(
                    named: "CIPhotoEffectChrome",
                    inputImage: sourceImage
                ) else { return nil }
                filteredImage = output
            case .instant:
                guard let output = processedImage(
                    named: "CIPhotoEffectInstant",
                    inputImage: sourceImage
                ) else { return nil }
                filteredImage = output
            case .mono:
                guard let output = processedImage(
                    named: "CIPhotoEffectMono",
                    inputImage: sourceImage
                ) else { return nil }
                filteredImage = output
            case .tonal:
                guard let output = processedImage(
                    named: "CIPhotoEffectTonal",
                    inputImage: sourceImage
                ) else { return nil }
                filteredImage = output
            case .noir:
                guard let output = processedImage(
                    named: "CIPhotoEffectNoir",
                    inputImage: sourceImage
                ) else { return nil }
                filteredImage = output
            case .thermal:
                guard let output = processedImage(
                    named: "CIThermal",
                    inputImage: sourceImage
                ) else { return nil }
                filteredImage = output
            case .xRay:
                guard let output = processedImage(
                    named: "CIXRay",
                    inputImage: sourceImage
                ) else { return nil }
                filteredImage = output
                
            case .comic:
                guard let output = processedImage(
                    named: "CIComicEffect",
                    inputImage: sourceImage
                ) else { return nil }
                filteredImage = output
            case .sketch:
                guard let output = processedImage(
                    named: "CILineOverlay",
                    inputImage: sourceImage,
                    parameters: [
                        "inputNRNoiseLevel": 0.05,
                        "inputNRSharpness": 0.5,
                        "inputEdgeIntensity": 0.7,
                        kCIInputThresholdKey: 0.05,
                        kCIInputContrastKey: 30.0
                    ]
                ) else { return nil }
                let whiteBackground = CIImage(color: .white).cropped(to: sourceImage.extent)
                let composited = output.composited(over: whiteBackground)
                filteredImage = croppedImage(composited, to: sourceImage.extent)
            case .lineScreen:
                guard let output = processedImage(
                    named: "CILineScreen",
                    inputImage: sourceImage,
                    parameters: [
                        kCIInputCenterKey: CIVector(x: sourceImage.extent.midX, y: sourceImage.extent.midY),
                        kCIInputAngleKey: 0.8,
                        kCIInputWidthKey: 35,
                        kCIInputSharpnessKey: 0.7
                    ]
                ) else { return nil }
                filteredImage = croppedImage(output, to: sourceImage.extent)
            case .pixellate:
                guard let output = processedImage(
                    named: "CIPixellate",
                    inputImage: sourceImage,
                    parameters: [
                        kCIInputCenterKey: CIVector(x: sourceImage.extent.midX, y: sourceImage.extent.midY),
                        kCIInputScaleKey: 25
                    ]
                ) else { return nil }
                filteredImage = croppedImage(output, to: sourceImage.extent)
            case .dither:
                guard let output = processedImage(
                    named: "CIDither",
                    inputImage: sourceImage,
                    parameters: [
                        kCIInputIntensityKey: 0.5
                    ]
                ) else { return nil }
                filteredImage = croppedImage(output, to: sourceImage.extent)
                
            case .twirlDistortion:
                guard let output = processedImage(
                    named: "CITwirlDistortion",
                    inputImage: sourceImage,
                    parameters: [
                        kCIInputAngleKey: 1.2,
                        kCIInputCenterKey: CIVector(x: sourceImage.extent.midX, y: sourceImage.extent.midY),
                        kCIInputRadiusKey: 1200
                    ]
                ) else { return nil }
                filteredImage = croppedImage(output, to: sourceImage.extent)
            case .motionBlur:
                guard let output = processedImage(
                    named: "CIMotionBlur",
                    inputImage: sourceImage,
                    parameters: [
                        kCIInputAngleKey: 0,
                        kCIInputRadiusKey: 40
                    ]
                ) else { return nil }
                filteredImage = croppedImage(output, to: sourceImage.extent)
            case .zoomBlur:
                guard let output = processedImage(
                    named: "CIZoomBlur",
                    inputImage: sourceImage,
                    parameters: [
                        kCIInputAmountKey: 15,
                        kCIInputCenterKey: CIVector(x: sourceImage.extent.midX, y: sourceImage.extent.midY),
                    ]
                ) else { return nil }
                filteredImage = croppedImage(output, to: sourceImage.extent)
                
            case .fisheye:
                guard let distorted = processedImage(
                    named: "CIBumpDistortion",
                    inputImage: sourceImage,
                    parameters: [
                        kCIInputCenterKey: CIVector(x: sourceImage.extent.midX, y: sourceImage.extent.midY),
                        kCIInputRadiusKey: min(sourceImage.extent.width, sourceImage.extent.height) * 1,
                        kCIInputScaleKey: 0.9
                    ]
                ) else { return nil }
                
                let squareRect = largestInscribedSquareBySampling(distorted)
                let squareCropped = croppedImage(distorted, to: squareRect)
                
                let imageSize = min(squareCropped.extent.width, squareCropped.extent.height)
                
                guard let radialGradient = CIFilter(name: "CIRadialGradient", parameters: [
                    kCIInputCenterKey: CIVector(x: squareCropped.extent.midX, y: squareCropped.extent.midY),
                    kCIInputRadius0Key: imageSize*0.45,
                    kCIInputRadius1Key: imageSize*0.5,
                    kCIInputColor0Key: CIColor(red: 0, green: 0, blue: 0, alpha: 0),
                    kCIInputColor1Key: CIColor(red: 0, green: 0, blue: 0, alpha: 1),
                ])?.outputImage?.cropped(to: squareCropped.extent) else { return nil }
                
                guard let vignetted = CIFilter(name: "CISourceOverCompositing", parameters: [
                    kCIInputImageKey: radialGradient,
                    kCIInputBackgroundImageKey: squareCropped
                ])?.outputImage else { return nil }
                
                filteredImage = vignetted
            case .droste:
                guard let output = processedImage(
                    named: "CIDroste",
                    inputImage: sourceImage,
                    parameters: [
                        "inputRotation": 0,
                        "inputZoom": 1,
                        "inputPeriodicity": 1,
                        "inputStrands": 1,
                        "inputInsetPoint1": CIVector(x: sourceImage.extent.size.width * 0.2, y: sourceImage.extent.size.height * 0.2),
                        "inputInsetPoint0": CIVector(x: sourceImage.extent.size.width * 0.8, y: sourceImage.extent.size.height * 0.8)
                    ]
                ) else { return nil }
                filteredImage = croppedImage(output, to: sourceImage.extent)
            case .lightTunnel:
                guard let output = processedImage(
                    named: "CILightTunnel",
                    inputImage: sourceImage,
                    parameters: [
                        kCIInputCenterKey: CIVector(x: sourceImage.extent.midX, y: sourceImage.extent.midY),
                        kCIInputRadiusKey: min(sourceImage.extent.width, sourceImage.extent.height) * 0.3,
                        "inputRotation": 3.14
                    ]
                ) else { return nil }
                filteredImage = croppedImage(output, to: sourceImage.extent)
            case .glassLozenge:
                guard let output = processedImage(
                    named: "CIGlassLozenge",
                    inputImage: sourceImage,
                    parameters: [
                        kCIInputRadiusKey: 450,
                        kCIInputRefractionKey: 1.7,
                        kCIInputPoint0Key: CIVector(x: sourceImage.extent.midX / 2, y: sourceImage.extent.midY / 2 * 3),
                        kCIInputPoint1Key: CIVector(x: sourceImage.extent.midX / 2 * 3, y: sourceImage.extent.midY / 2)
                    ]
                ) else { return nil }
                filteredImage = croppedImage(output, to: sourceImage.extent)
        }
        
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
        // Downsample for fast scanning
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
        
        // Helper to get alpha at (x, y)
        func alphaAt(_ x: Int, _ y: Int) -> CGFloat {
            let idx = (y * width + x) * 4 + 3
            return CGFloat(rgba[idx]) / 255.0
        }
        
        // Scan from edges toward center along the middle row/column
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
        
        // Convert bounds back to full-res
        let leftF = CGFloat(left) / scaleX
        let rightF = CGFloat(right) / scaleX
        let bottomF = CGFloat(bottom) / scaleY
        let topF = CGFloat(top) / scaleY
        
        // Tight content bounds
        let contentMinX = max(extent.minX, extent.minX + leftF)
        let contentMaxX = min(extent.maxX, extent.minX + rightF)
        let contentMinY = max(extent.minY, extent.minY + bottomF)
        let contentMaxY = min(extent.maxY, extent.minY + topF)
        
        let contentWidth = max(0, contentMaxX - contentMinX)
        let contentHeight = max(0, contentMaxY - contentMinY)
        
        // Largest centered square inside these bounds
        let side = min(contentWidth, contentHeight)
        let centerX = (contentMinX + contentMaxX) * 0.5
        // let centerY = (contentMinY + contentMaxY) * 0.5
        let square = CGRect(x: -centerX, y: 2*centerX, width: side, height: side)
        
        return square.integral
    }
}
