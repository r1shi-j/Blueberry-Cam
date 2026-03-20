internal import AVFoundation
import CoreImage
import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers

extension CameraModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        if let error {
            Task { @MainActor in self.errorMessage = error.localizedDescription; self.showError = true }
            return
        }
        guard let data = photo.fileDataRepresentation() else {
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
        }
    }
    
    private nonisolated func saveToPhotos(data: Data, location: CLLocation?, isDNG: Bool, isHEIF: Bool = false) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in self.errorMessage = "Photos access denied."; self.showError = true }
                return
            }
            
            // 1. Resolve the "Blueberry Cam" album, creating it only when necessary.
            let albumID = resolveAlbumID()
            let album = albumID.flatMap {
                PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [$0], options: nil).firstObject
            }
            
            PHPhotoLibrary.shared().performChanges({
                let opts = PHAssetResourceCreationOptions()
                opts.uniformTypeIdentifier = BundleIDs.UTI(isDNG: isDNG, isHEIF: isHEIF)
                let req = PHAssetCreationRequest.forAsset()
                if let loc = location {
                    req.location = loc
                }
                req.addResource(with: .photo, data: data, options: opts)
                
                // 2. Add the new asset to the album
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
            case .dither:
                guard let output = processedImage(
                    named: "CIDither",
                    inputImage: sourceImage,
                    parameters: [
                        kCIInputIntensityKey: 0.5
                    ]
                ) else { return nil }
                filteredImage = croppedImage(output, to: sourceImage.extent)
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
            case .bumpDistortion:
                guard let output = processedImage(
                    named: "CIBumpDistortion",
                    inputImage: sourceImage,
                    parameters: [
                        kCIInputRadiusKey: 1500,
                        kCIInputCenterKey: CIVector(x: sourceImage.extent.midX, y: sourceImage.extent.midY),
                        kCIInputScaleKey: 1.2
                    ]
                ) else { return nil }
                filteredImage = croppedImage(output, to: sourceImage.extent)
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
            case .comic:
                guard let output = processedImage(
                    named: "CIComicEffect",
                    inputImage: sourceImage
                ) else { return nil }
                filteredImage = output
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
            case .lineOverlay:
                guard let output = processedImage(
                    named: "CILineOverlay",
                    inputImage: sourceImage,
                    parameters: [
                        "inputNRNoiseLevel": 0.07,
                        "inputNRSharpness": 0.71,
                        "inputEdgeIntensity": 1,
                        kCIInputThresholdKey: 0.1,
                        kCIInputContrastKey: 50.00
                    ]
                ) else { return nil }
                let whiteBackground = CIImage(color: .white).cropped(to: sourceImage.extent)
                let composited = output.composited(over: whiteBackground)
                filteredImage = croppedImage(composited, to: sourceImage.extent)
            case .kaleidoscope:
                guard let output = processedImage(
                    named: "CIKaleidoscope",
                    inputImage: sourceImage,
                    parameters: [
                        kCIInputCenterKey: CIVector(x: sourceImage.extent.midX, y: sourceImage.extent.midY),
                        kCIInputAngleKey: 0,
                        kCIInputCountKey: 8
                    ]
                ) else { return nil }
                filteredImage = croppedImage(output, to: sourceImage.extent)
            case .fisheye:
                guard let output = processedImage(
                    named: "CIBumpDistortion",
                    inputImage: sourceImage,
                    parameters: [
                        kCIInputCenterKey: CIVector(x: sourceImage.extent.midX, y: sourceImage.extent.midY),
                        kCIInputRadiusKey: min(sourceImage.extent.width, sourceImage.extent.height) * 1.5,
                        kCIInputScaleKey: 0.9 // positive for outward bulge (fisheye)
                    ]
                ) else { return nil }
                let cropped = croppedImage(output, to: sourceImage.extent)
                let circleMaskedImage: CIImage = {
                    let extent = cropped.extent
                    let center = CIVector(x: extent.midX, y: extent.midY)
                    let radius = min(extent.width, extent.height) * 0.5
                    // Create a hard-edged radial gradient mask (white inside, black outside)
                    let gradient = CIFilter(name: "CIRadialGradient", parameters: [
                        kCIInputCenterKey: center,
                        "inputRadius0": radius - 0.5,
                        "inputRadius1": radius + 0.5,
                        "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 1),
                        "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0)
                    ])?.outputImage?.cropped(to: extent) ?? CIImage(color: .white).cropped(to: extent)
                    
                    // Keep only pixels where the mask is white (inside the circle)
                    let masked = cropped.applyingFilter("CIBlendWithMask", parameters: [
                        kCIInputBackgroundImageKey: CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: extent),
                        kCIInputMaskImageKey: gradient
                    ])
                    return masked
                }()
                
                filteredImage = circleMaskedImage
        }
        
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let context = CIContext()
        guard let cgImage = context.createCGImage(filteredImage, from: filteredImage.extent, format: .RGBA8, colorSpace: colorSpace) else {
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
}
