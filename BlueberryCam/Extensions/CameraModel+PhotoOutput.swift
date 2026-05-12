internal import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
internal import Photos
import UniformTypeIdentifiers

extension CameraModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        guard let onCapture = self._captureContextStore.context(for: resolvedSettings.uniqueID)?.onCapture else { return }
        
        Task { @MainActor in
            onCapture()
        }
    }
    
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        self._burstCaptureTracker.completeSensorCapture(uniqueID: resolvedSettings.uniqueID, success: true)
    }
    
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        let uniqueID = photo.resolvedSettings.uniqueID
        let context = self._captureContextStore.context(for: uniqueID) ?? PhotoCaptureContext(
            captureMode: self._pendingCaptureModeBox.value,
            photoFilter: self._pendingPhotoFilterBox.value,
            saveLocation: self._pendingSaveLocationBox.value,
            isBurst: false,
            burstSessionID: nil,
            isDualCameraCapture: false,
            dualCameraPipPlacement: .topTrailing,
            dualCameraPipRotationAngle: 0,
            onCapture: nil
        )
        if let error {
            self._burstCaptureTracker.completeProcessing(uniqueID: uniqueID, success: false)
            reportCaptureFailure(error, context: context, uniqueID: uniqueID, phase: "processing")
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            self._burstCaptureTracker.completeProcessing(uniqueID: uniqueID, success: false)
            reportCaptureFailure("Failed to get photo data.", context: context, uniqueID: uniqueID, phase: "file data")
            return
        }
        self._captureContextStore.markPhotoDataProduced(for: uniqueID)
        let isHeif = !photo.isRawPhoto && context.captureMode == .heif
        let photoFilter = context.photoFilter
        Task {
            let loc = await MainActor.run {
                self.recordBurstPhotoDataProduced(context: context)
                return self.currentLocation
            }
            let filteredData = self.filteredPhotoDataIfNeeded(
                from: data,
                filter: photoFilter,
                isRaw: photo.isRawPhoto,
                isHEIF: isHeif
            ) ?? data
            let outputData = self.dualCameraPhotoDataIfNeeded(
                from: filteredData,
                context: context,
                isDNG: photo.isRawPhoto,
                isHEIF: isHeif
            ) ?? filteredData
            switch context.saveLocation {
                case .photos:
                    self.saveToPhotos(data: outputData, location: loc, isDNG: photo.isRawPhoto, isHEIF: isHeif, context: context)
                case .files:
                    self.saveToFiles(data: outputData, location: loc, isDNG: photo.isRawPhoto, isHEIF: isHeif, context: context)
            }
            self._burstCaptureTracker.completeProcessing(uniqueID: uniqueID, success: true)
        }
    }
    
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                                 error: Error?) {
        let uniqueID = resolvedSettings.uniqueID
        let context = self._captureContextStore.context(for: uniqueID) ?? PhotoCaptureContext(
            captureMode: self._pendingCaptureModeBox.value,
            photoFilter: self._pendingPhotoFilterBox.value,
            saveLocation: self._pendingSaveLocationBox.value,
            isBurst: false,
            burstSessionID: nil,
            isDualCameraCapture: false,
            dualCameraPipPlacement: .topTrailing,
            dualCameraPipRotationAngle: 0,
            onCapture: nil
        )
        guard let error else {
            _ = self._captureContextStore.removeContext(for: uniqueID)
            return
        }
        if self._captureContextStore.hasProducedPhotoData(for: uniqueID) {
            _ = self._captureContextStore.removeContext(for: uniqueID)
            return
        }
        self._burstCaptureTracker.completeSensorCapture(uniqueID: uniqueID, success: false)
        self._burstCaptureTracker.completeProcessing(uniqueID: uniqueID, success: false)
        reportCaptureFailure(error, context: context, uniqueID: uniqueID, phase: "capture")
        _ = self._captureContextStore.removeContext(for: uniqueID)
    }
    
    private nonisolated func saveToPhotos(data: Data,
                                          location: CLLocation?,
                                          isDNG: Bool,
                                          isHEIF: Bool = false,
                                          context: PhotoCaptureContext) {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        
        guard currentStatus == .authorized || currentStatus == .limited else {
            reportSaveFailure("Photos access denied. Please enable in Settings.", context: context)
            return
        }
        
        performSave(data: data, location: location, isDNG: isDNG, isHEIF: isHEIF, context: context)
    }
    
    private nonisolated func saveToFiles(data: Data,
                                         location: CLLocation?,
                                         isDNG: Bool,
                                         isHEIF: Bool,
                                         context: PhotoCaptureContext) {
        do {
            let destination = try FileSaveLocationStore.makeDestinationURL(isDNG: isDNG, isHEIF: isHEIF)
            defer { destination.stopAccessing() }
            let outputData = dataWithLocationMetadataIfNeeded(data, location: location, isDNG: isDNG)
            try outputData.write(to: destination.url, options: .atomic)
            reportSaveSuccess(context: context)
        } catch {
            reportFileSaveFailure(error, context: context)
        }
    }
    
    private nonisolated func performSave(data: Data,
                                         location: CLLocation? = nil,
                                         isDNG: Bool,
                                         isHEIF: Bool,
                                         context: PhotoCaptureContext) {
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
            if success {
                self.reportSaveSuccess(context: context)
            } else {
                if let error {
                    self.reportSaveFailure(error, context: context)
                } else {
                    self.reportSaveFailure("Unknown save error.", context: context)
                }
            }
        }
    }
    
    private nonisolated func reportCaptureFailure(_ error: Error,
                                                  context: PhotoCaptureContext,
                                                  uniqueID: Int64,
                                                  phase: String) {
        let nsError = error as NSError
        let diagnostics = "\(error.localizedDescription) (\(nsError.domain) \(nsError.code))"
        reportCaptureFailure(
            diagnostics,
            context: context,
            uniqueID: uniqueID,
            phase: phase,
            isGenericAVFoundationFailure: nsError.domain == AVFoundationErrorDomain && nsError.code == -11800
        )
    }
    
    private nonisolated func reportCaptureFailure(_ message: String,
                                                  context: PhotoCaptureContext,
                                                  uniqueID: Int64,
                                                  phase: String,
                                                  isGenericAVFoundationFailure: Bool = false) {
        let shouldReportBurstFailure = context.isBurst && self._captureContextStore.markCaptureFailureIfNeeded(for: uniqueID)
        Task { @MainActor in
            if context.isBurst {
                guard shouldReportBurstFailure else { return }
                guard !self.shouldIgnoreBurstCaptureFailure(context: context, uniqueID: uniqueID) else { return }
                self.recordBurstCaptureFailure(context: context)
            } else if isGenericAVFoundationFailure, self.shouldSuppressGenericCaptureErrorAsBurstTail() {
                return
            } else {
                self.errorMessage = message
                self.showError = true
            }
        }
    }
    
    private nonisolated func reportSaveSuccess(context: PhotoCaptureContext) {
        Task { @MainActor in
            if context.isBurst {
                self.recordBurstSaveSuccess(context: context)
            } else {
                self.onStandardPhotoSaved?()
            }
        }
    }
    
    private nonisolated func reportSaveFailure(_ error: Error, context: PhotoCaptureContext) {
        let nsError = error as NSError
        let diagnostics = "\(error.localizedDescription) (\(nsError.domain) \(nsError.code))"
        reportSaveFailure(diagnostics, context: context)
    }
    
    private nonisolated func reportFileSaveFailure(_ error: Error, context: PhotoCaptureContext) {
        Task { @MainActor in
            self.recoverFromFileSaveLocationFailure(error)
            if context.isBurst {
                self.recordBurstSaveFailure(context: context)
            }
        }
    }
    
    private nonisolated func reportSaveFailure(_ message: String, context: PhotoCaptureContext) {
        Task { @MainActor in
            if context.isBurst {
                self.recordBurstSaveFailure(context: context)
            } else {
                self.errorMessage = message
                self.showError = true
            }
        }
    }
    
    private nonisolated func dualCameraPhotoDataIfNeeded(from data: Data,
                                                         context: PhotoCaptureContext,
                                                         isDNG: Bool,
                                                         isHEIF: Bool) -> Data? {
        guard context.isDualCameraCapture, !isDNG else { return nil }
        guard let pipPixelBuffer = _secondaryFrameStore.currentPixelBuffer() else { return nil }
        
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let mainImage = orientedImage(from: source) else { return nil }
        
        let ciContext = CIContext(options: [.cacheIntermediates: false])
        let pipImage = CIImage(cvPixelBuffer: pipPixelBuffer)
        guard let pipCGImage = ciContext.createCGImage(pipImage, from: pipImage.extent) else { return nil }
        guard let compositedImage = compositedDualCameraImage(
            mainImage: mainImage,
            pipImage: pipCGImage,
            pipPlacement: context.dualCameraPipPlacement,
            pipRotationAngle: context.dualCameraPipRotationAngle
        ) else { return nil }
        
        let outputData = NSMutableData()
        let outputType = isHEIF ? UTType.heic.identifier : UTType.jpeg.identifier
        guard let destination = CGImageDestinationCreateWithData(outputData, outputType as CFString, 1, nil) else {
            return nil
        }
        
        var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        properties[kCGImagePropertyOrientation] = CGImagePropertyOrientation.up.rawValue
        properties[kCGImageDestinationLossyCompressionQuality] = 0.95
        CGImageDestinationAddImage(destination, compositedImage, properties as CFDictionary)
        addHDRGainMapIfPresent(from: source, to: destination)
        guard CGImageDestinationFinalize(destination) else { return nil }
        
        return outputData as Data
    }
    
    private nonisolated func addHDRGainMapIfPresent(from source: CGImageSource,
                                                    to destination: CGImageDestination) {
        if let isoGainMap = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeISOGainMap) {
            CGImageDestinationAddAuxiliaryDataInfo(destination, kCGImageAuxiliaryDataTypeISOGainMap, isoGainMap)
            return
        }
        
        if let hdrGainMap = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeHDRGainMap) {
            CGImageDestinationAddAuxiliaryDataInfo(destination, kCGImageAuxiliaryDataTypeHDRGainMap, hdrGainMap)
        }
    }
    
    private nonisolated func orientedImage(from source: CGImageSource) -> CGImage? {
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        let rawOrientation = properties[kCGImagePropertyOrientation] as? UInt32
        let orientation = rawOrientation.flatMap(CGImagePropertyOrientation.init(rawValue:)) ?? .up
        guard orientation != .up else { return cgImage }
        
        let ciContext = CIContext(options: [.cacheIntermediates: false])
        let orientedImage = CIImage(cgImage: cgImage).oriented(orientation)
        return ciContext.createCGImage(orientedImage, from: orientedImage.extent)
    }
    
    private nonisolated func compositedDualCameraImage(mainImage: CGImage,
                                                       pipImage: CGImage,
                                                       pipPlacement: DualCameraPipPlacement,
                                                       pipRotationAngle: CGFloat) -> CGImage? {
        let width = mainImage.width
        let height = mainImage.height
        let colorSpace = mainImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(mainImage, in: canvas)
        
        let rotatedPipImage = rotatedRightAngleImage(pipImage, by: pipRotationAngle) ?? pipImage
        let pipAspectRatio = pipAspectRatio(for: pipRotationAngle)
        let pipWidth = CGFloat(width) * 0.32
        let pipHeight = pipWidth / pipAspectRatio
        let inset = CGFloat(width) * 0.035
        let displayPlacement = photoPlacement(pipPlacement, for: pipRotationAngle)
        let pipRect = displayPlacement.photoRect(
            in: CGSize(width: CGFloat(width), height: CGFloat(height)),
            pipSize: CGSize(width: pipWidth, height: pipHeight),
            inset: inset
        )
        let cornerRadius = pipWidth * 0.20
        let rimWidth = max(1.5, pipWidth * 0.006)
        let innerRect = pipRect.insetBy(dx: rimWidth, dy: rimWidth)
        let innerCornerRadius = max(0, cornerRadius - rimWidth)
        let outerPath = CGPath(
            roundedRect: pipRect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        let innerPath = CGPath(
            roundedRect: innerRect,
            cornerWidth: innerCornerRadius,
            cornerHeight: innerCornerRadius,
            transform: nil
        )
        
        context.setFillColor(CGColor(red: 0.30, green: 0.28, blue: 0.24, alpha: 0.32))
        context.addPath(outerPath)
        context.fillPath()
        
        context.saveGState()
        context.addPath(innerPath)
        context.clip()
        drawAspectFill(image: rotatedPipImage, in: innerRect, context: context)
        context.restoreGState()
        
        context.setStrokeColor(CGColor(red: 0.42, green: 0.39, blue: 0.34, alpha: 0.70))
        context.setLineWidth(max(0.75, pipWidth * 0.0012))
        context.addPath(outerPath)
        context.strokePath()
        
        context.setStrokeColor(CGColor(red: 0.08, green: 0.07, blue: 0.06, alpha: 0.28))
        context.setLineWidth(max(0.75, pipWidth * 0.0008))
        context.addPath(innerPath)
        context.strokePath()
        
        return context.makeImage()
    }
    
    private nonisolated func rotatedRightAngleImage(_ image: CGImage, by degrees: CGFloat) -> CGImage? {
        let normalizedDegrees = nearestRightAngle(degrees)
        let orientation: CGImagePropertyOrientation
        if normalizedDegrees == 90 {
            orientation = .right
        } else if normalizedDegrees == 180 {
            orientation = .down
        } else if normalizedDegrees == 270 {
            orientation = .left
        } else {
            return image
        }
        
        let ciContext = CIContext(options: [.cacheIntermediates: false])
        let rotatedImage = CIImage(cgImage: image).oriented(orientation)
        return ciContext.createCGImage(rotatedImage, from: rotatedImage.extent)
    }
    
    private nonisolated func pipAspectRatio(for rotationAngle: CGFloat) -> CGFloat {
        if isQuarterTurn(rotationAngle) {
            return 4.0 / 3.0
        }
        
        return 3.0 / 4.0
    }
    
    private nonisolated func photoPlacement(_ placement: DualCameraPipPlacement,
                                            for rotationAngle: CGFloat) -> DualCameraPipPlacement {
        let normalizedDegrees = nearestRightAngle(rotationAngle)
        if normalizedDegrees == 90 {
            return placement.rotatedClockwise
        }
        if normalizedDegrees == 180 {
            return placement.opposite
        }
        if normalizedDegrees == 270 {
            return placement.rotatedCounterclockwise
        }
        
        return placement
    }
    
    private nonisolated func isQuarterTurn(_ degrees: CGFloat) -> Bool {
        let normalizedDegrees = nearestRightAngle(degrees)
        return normalizedDegrees == 90 || normalizedDegrees == 270
    }
    
    private nonisolated func nearestRightAngle(_ degrees: CGFloat) -> CGFloat {
        let normalizedDegrees = normalizedRotationAngle(degrees)
        return normalizedRotationAngle((normalizedDegrees / 90).rounded() * 90)
    }
    
    private nonisolated func normalizedRotationAngle(_ degrees: CGFloat) -> CGFloat {
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }
    
    private nonisolated func drawAspectFill(image: CGImage, in rect: CGRect, context: CGContext) {
        let sourceSize = CGSize(width: image.width, height: image.height)
        guard sourceSize.width > 0, sourceSize.height > 0 else { return }
        
        let scale = max(rect.width / sourceSize.width, rect.height / sourceSize.height)
        let drawSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let drawRect = CGRect(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        context.draw(image, in: drawRect)
    }
    
    private nonisolated func dataWithLocationMetadataIfNeeded(_ data: Data,
                                                              location: CLLocation?,
                                                              isDNG: Bool) -> Data {
        guard let location,
              !isDNG,
              CLLocationCoordinate2DIsValid(location.coordinate),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let sourceType = CGImageSourceGetType(source) else {
            return data
        }
        
        var metadata = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        var gpsMetadata: [CFString: Any] = [
            kCGImagePropertyGPSLatitude: abs(location.coordinate.latitude),
            kCGImagePropertyGPSLatitudeRef: location.coordinate.latitude >= 0 ? "N" : "S",
            kCGImagePropertyGPSLongitude: abs(location.coordinate.longitude),
            kCGImagePropertyGPSLongitudeRef: location.coordinate.longitude >= 0 ? "E" : "W"
        ]
        
        if location.altitude != 0 {
            gpsMetadata[kCGImagePropertyGPSAltitude] = abs(location.altitude)
            gpsMetadata[kCGImagePropertyGPSAltitudeRef] = location.altitude < 0 ? 1 : 0
        }
        
        metadata[kCGImagePropertyGPSDictionary] = gpsMetadata
        
        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(outputData, sourceType, 1, nil) else {
            return data
        }
        
        CGImageDestinationAddImageFromSource(destination, source, 0, metadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return data
        }
        
        return outputData as Data
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
            case .sepia:
                guard let output = processedImage(
                    named: "CISepiaTone",
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
                guard let output = thermalImage(from: sourceImage) else { return nil }
                filteredImage = output
            case .xRay:
                guard let output = xRayImage(from: sourceImage) else { return nil }
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
    
    private nonisolated func thermalImage(from sourceImage: CIImage) -> CIImage? {
        guard let rangeExpandedImage = toneCurveImage(
            sourceImage,
            point0: CIVector(x: 0, y: 0),
            point1: CIVector(x: 0.18, y: 0.34),
            point2: CIVector(x: 0.45, y: 0.64),
            point3: CIVector(x: 0.75, y: 0.88),
            point4: CIVector(x: 1, y: 1)
        ),
              let primedImage = colorControlledImage(
                rangeExpandedImage,
                saturation: 1,
                brightness: 0,
                contrast: 1.08
              ),
              let invertedImage = processedImage(named: "CIColorInvert", inputImage: primedImage),
              let thermalImage = processedImage(named: "CIThermal", inputImage: invertedImage),
              let vibrantImage = vibranceImage(thermalImage, amount: 0.55),
              let warmerImage = colorMatrixImage(
                vibrantImage,
                red: 1.18,
                green: 1.04,
                blue: 0.68,
                redBias: 0.02,
                blueBias: -0.015
              ),
              let punchedImage = colorControlledImage(
                warmerImage,
                saturation: 1.6,
                brightness: 0.01,
                contrast: 1.16
              ) else { return nil }
        
        return sharpenedImage(punchedImage, sharpness: 0.18).map { croppedImage($0, to: sourceImage.extent) }
    }
    
    private nonisolated func xRayImage(from sourceImage: CIImage) -> CIImage? {
        guard let primedImage = colorControlledImage(
            sourceImage,
            saturation: 1,
            brightness: -0.05,
            contrast: 0.8
        ),
              let xRayImage = processedImage(named: "CIXRay", inputImage: primedImage),
              let shapedImage = toneCurveImage(
                xRayImage,
                point0: CIVector(x: 0, y: 0),
                point1: CIVector(x: 0.26, y: 0.06),
                point2: CIVector(x: 0.55, y: 0.32),
                point3: CIVector(x: 0.82, y: 0.54),
                point4: CIVector(x: 1, y: 0.78)
              ),
              let darkenedImage = gammaAdjustedImage(shapedImage, power: 1.22),
              let tintedImage = colorMatrixImage(
                darkenedImage,
                red: 0.64,
                green: 0.88,
                blue: 1.12,
                redBias: -0.015,
                greenBias: -0.02,
                blueBias: 0.018
              ),
              let punchedImage = colorControlledImage(
                tintedImage,
                saturation: 1,
                brightness: 0,
                contrast: 1.18
              ) else { return nil }
        
        return sharpenedImage(punchedImage, sharpness: 0.35).map { croppedImage($0, to: sourceImage.extent) }
    }
    
    private nonisolated func colorControlledImage(_ inputImage: CIImage,
                                                  saturation: CGFloat,
                                                  brightness: CGFloat,
                                                  contrast: CGFloat) -> CIImage? {
        processedImage(
            named: "CIColorControls",
            inputImage: inputImage,
            parameters: [
                kCIInputSaturationKey: saturation,
                kCIInputBrightnessKey: brightness,
                kCIInputContrastKey: contrast
            ]
        )
    }
    
    private nonisolated func gammaAdjustedImage(_ inputImage: CIImage, power: CGFloat) -> CIImage? {
        processedImage(
            named: "CIGammaAdjust",
            inputImage: inputImage,
            parameters: ["inputPower": power]
        )
    }
    
    private nonisolated func toneCurveImage(_ inputImage: CIImage,
                                            point0: CIVector,
                                            point1: CIVector,
                                            point2: CIVector,
                                            point3: CIVector,
                                            point4: CIVector) -> CIImage? {
        processedImage(
            named: "CIToneCurve",
            inputImage: inputImage,
            parameters: [
                "inputPoint0": point0,
                "inputPoint1": point1,
                "inputPoint2": point2,
                "inputPoint3": point3,
                "inputPoint4": point4
            ]
        )
    }
    
    private nonisolated func vibranceImage(_ inputImage: CIImage, amount: CGFloat) -> CIImage? {
        processedImage(
            named: "CIVibrance",
            inputImage: inputImage,
            parameters: ["inputAmount": amount]
        )
    }
    
    private nonisolated func colorMatrixImage(_ inputImage: CIImage,
                                              red: CGFloat,
                                              green: CGFloat,
                                              blue: CGFloat,
                                              redBias: CGFloat,
                                              greenBias: CGFloat = 0,
                                              blueBias: CGFloat) -> CIImage? {
        processedImage(
            named: "CIColorMatrix",
            inputImage: inputImage,
            parameters: [
                "inputRVector": CIVector(x: red, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: green, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: blue, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: redBias, y: greenBias, z: blueBias, w: 0)
            ]
        )
    }
    
    private nonisolated func sharpenedImage(_ inputImage: CIImage, sharpness: CGFloat) -> CIImage? {
        processedImage(
            named: "CISharpenLuminance",
            inputImage: inputImage,
            parameters: [kCIInputSharpnessKey: sharpness]
        )
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
