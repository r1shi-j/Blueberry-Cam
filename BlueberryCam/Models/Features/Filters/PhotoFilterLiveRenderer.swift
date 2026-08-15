import CoreImage
import Foundation

struct PhotoFilterLiveRenderer {
    func filteredImage(from sourceImage: CIImage, filter: PhotoFilter, retroMegaPixels: Float = 0.3, referenceSize: CGSize) -> CIImage? {
        let previewScale = previewScale(for: sourceImage.extent, referenceSize: referenceSize)
        
        return switch filter {
            case .off:
                sourceImage
            case .retro:
                retroImage(from: sourceImage, megaPixels: retroMegaPixels, previewScale: previewScale)
            case .temperatureAndTint:
                processedImage(
                    named: "CITemperatureAndTint",
                    inputImage: sourceImage,
                    parameters: [
                        "inputNeutral": CIVector(x: 11500, y: 16),
                        "inputTargetNeutral": CIVector(x: 5000, y: 0)
                    ]
                )?.cropped(to: sourceImage.extent)
            case .chrome:
                processedImage(named: "CIPhotoEffectChrome", inputImage: sourceImage)
            case .instant:
                processedImage(named: "CIPhotoEffectInstant", inputImage: sourceImage)
            case .sepia:
                processedImage(named: "CISepiaTone", inputImage: sourceImage)
            case .mono:
                processedImage(named: "CIPhotoEffectMono", inputImage: sourceImage)
            case .tonal:
                processedImage(named: "CIPhotoEffectTonal", inputImage: sourceImage)
            case .noir:
                processedImage(named: "CIPhotoEffectNoir", inputImage: sourceImage)
            case .thermal:
                thermalImage(from: sourceImage)
            case .xRay:
                xRayImage(from: sourceImage)
            case .comic:
                processedImage(named: "CIComicEffect", inputImage: sourceImage)
            case .sketch:
                sketchImage(from: sourceImage)
            case .lineScreen:
                processedImage(
                    named: "CILineScreen",
                    inputImage: sourceImage,
                    parameters: [
                        kCIInputCenterKey: CIVector(x: sourceImage.extent.midX, y: sourceImage.extent.midY),
                        kCIInputAngleKey: 0.8,
                        kCIInputWidthKey: scaled(35, by: previewScale),
                        kCIInputSharpnessKey: 0.7
                    ]
                )?.cropped(to: sourceImage.extent)
            case .pixellate:
                processedImage(
                    named: "CIPixellate",
                    inputImage: sourceImage,
                    parameters: [
                        kCIInputCenterKey: CIVector(x: sourceImage.extent.midX, y: sourceImage.extent.midY),
                        kCIInputScaleKey: scaled(25, by: previewScale)
                    ]
                )?.cropped(to: sourceImage.extent)
            case .dither:
                processedImage(
                    named: "CIDither",
                    inputImage: sourceImage,
                    parameters: [kCIInputIntensityKey: 0.5]
                )?.cropped(to: sourceImage.extent)
            case .twirlDistortion:
                processedImage(
                    named: "CITwirlDistortion",
                    inputImage: sourceImage,
                    parameters: [
                        kCIInputAngleKey: 1.2,
                        kCIInputCenterKey: CIVector(x: sourceImage.extent.midX, y: sourceImage.extent.midY),
                        kCIInputRadiusKey: scaled(1200, by: previewScale)
                    ]
                )?.cropped(to: sourceImage.extent)
            case .motionBlur:
                processedImage(
                    named: "CIMotionBlur",
                    inputImage: sourceImage,
                    parameters: [
                        kCIInputAngleKey: 0,
                        kCIInputRadiusKey: scaled(40, by: previewScale)
                    ]
                )?.cropped(to: sourceImage.extent)
            case .zoomBlur:
                processedImage(
                    named: "CIZoomBlur",
                    inputImage: sourceImage,
                    parameters: [
                        kCIInputAmountKey: scaled(15, by: previewScale),
                        kCIInputCenterKey: CIVector(x: sourceImage.extent.midX, y: sourceImage.extent.midY)
                    ]
                )?.cropped(to: sourceImage.extent)
            case .fisheye:
                fisheyeImage(from: sourceImage)
            case .droste:
                processedImage(
                    named: "CIDroste",
                    inputImage: sourceImage,
                    parameters: [
                        "inputRotation": 0,
                        "inputZoom": 1,
                        "inputPeriodicity": 1,
                        "inputStrands": 1,
                        "inputInsetPoint1": CIVector(x: sourceImage.extent.width * 0.2, y: sourceImage.extent.height * 0.2),
                        "inputInsetPoint0": CIVector(x: sourceImage.extent.width * 0.8, y: sourceImage.extent.height * 0.8)
                    ]
                )?.cropped(to: sourceImage.extent)
            case .lightTunnel:
                processedImage(
                    named: "CILightTunnel",
                    inputImage: sourceImage,
                    parameters: [
                        kCIInputCenterKey: CIVector(x: sourceImage.extent.midX, y: sourceImage.extent.midY),
                        kCIInputRadiusKey: min(sourceImage.extent.width, sourceImage.extent.height) * 0.3,
                        "inputRotation": 3.14
                    ]
                )?.cropped(to: sourceImage.extent)
            case .glassLozenge:
                processedImage(
                    named: "CIGlassLozenge",
                    inputImage: sourceImage,
                    parameters: [
                        kCIInputRadiusKey: scaled(450, by: previewScale),
                        kCIInputRefractionKey: 1.7,
                        kCIInputPoint0Key: CIVector(x: sourceImage.extent.midX / 2, y: sourceImage.extent.midY / 2 * 3),
                        kCIInputPoint1Key: CIVector(x: sourceImage.extent.midX / 2 * 3, y: sourceImage.extent.midY / 2)
                    ]
                )?.cropped(to: sourceImage.extent)
        }
    }
    
    private func previewScale(for sourceExtent: CGRect, referenceSize: CGSize) -> CGFloat {
        let sourceShortSide = min(abs(sourceExtent.width), abs(sourceExtent.height))
        let referenceShortSide = min(abs(referenceSize.width), abs(referenceSize.height))
        guard sourceShortSide > 0, referenceShortSide > 0 else { return 1 }
        return sourceShortSide / referenceShortSide
    }
    
    private func scaled(_ value: CGFloat, by previewScale: CGFloat) -> CGFloat {
        max(value * previewScale, 0.001)
    }
    
    private func thermalImage(from sourceImage: CIImage) -> CIImage? {
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
        
        return sharpenedImage(punchedImage, sharpness: 0.18)?.cropped(to: sourceImage.extent)
    }
    
    private func xRayImage(from sourceImage: CIImage) -> CIImage? {
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
        
        return sharpenedImage(punchedImage, sharpness: 0.35)?.cropped(to: sourceImage.extent)
    }
    
    private func sketchImage(from sourceImage: CIImage) -> CIImage? {
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
        return output.composited(over: whiteBackground).cropped(to: sourceImage.extent)
    }
    
    private func fisheyeImage(from sourceImage: CIImage) -> CIImage? {
        guard let distorted = processedImage(
            named: "CIBumpDistortion",
            inputImage: sourceImage,
            parameters: [
                kCIInputCenterKey: CIVector(x: sourceImage.extent.midX, y: sourceImage.extent.midY),
                kCIInputRadiusKey: min(sourceImage.extent.width, sourceImage.extent.height),
                kCIInputScaleKey: 0.9
            ]
        )?.cropped(to: sourceImage.extent) else { return nil }
        
        let imageSize = min(sourceImage.extent.width, sourceImage.extent.height)
        guard let radialGradient = CIFilter(name: "CIRadialGradient", parameters: [
            kCIInputCenterKey: CIVector(x: sourceImage.extent.midX, y: sourceImage.extent.midY),
            kCIInputRadius0Key: imageSize * 0.45,
            kCIInputRadius1Key: imageSize * 0.5,
            kCIInputColor0Key: CIColor(red: 0, green: 0, blue: 0, alpha: 0),
            kCIInputColor1Key: CIColor(red: 0, green: 0, blue: 0, alpha: 1)
        ])?.outputImage?.cropped(to: sourceImage.extent) else { return distorted }
        
        return CIFilter(name: "CISourceOverCompositing", parameters: [
            kCIInputImageKey: radialGradient,
            kCIInputBackgroundImageKey: distorted
        ])?.outputImage?.cropped(to: sourceImage.extent)
    }
    
    private func retroImage(from sourceImage: CIImage, megaPixels: Float, previewScale: CGFloat) -> CIImage? {
        let clampedMP = max(0.01, min(12.0, Double(megaPixels)))
        let extent = sourceImage.extent
        let aspectRatio = extent.height > 0 ? extent.width / extent.height : (4.0 / 3.0)
        
        let targetPixels = clampedMP * 1_000_000.0
        let targetHeight = max(24.0, round(sqrt(targetPixels / Double(aspectRatio))))
        let targetWidth = max(32.0, round(targetHeight * Double(aspectRatio)))
        
        let scaleX = targetWidth / extent.width
        let scaleY = targetHeight / extent.height
        
        let resized = sourceImage
            .samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        let targetExtent = CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
        let croppedResized = resized.cropped(to: targetExtent)
        
        let k = retroInterpolationFactor(for: clampedMP)
        
        // 1. Exposure lift / blown-out highlight white point
        let exposed = processedImage(
            named: "CIExposureAdjust",
            inputImage: croppedResized,
            parameters: [kCIInputEVKey: 0.30 + 0.18 * k]
        ) ?? croppedResized
        
        // 2. Optical softness / blur (Disabled - commented out for future use)
        let softOptical: CIImage = exposed
        /*
        let softOptical: CIImage
        if k > 0.1 {
            let blurRadius = min(0.04, 0.04 * k)
            softOptical = processedImage(
                named: "CIGaussianBlur",
                inputImage: exposed,
                parameters: [kCIInputRadiusKey: blurRadius]
            )?.cropped(to: targetExtent) ?? exposed
        } else {
            softOptical = exposed
        }
        */
        
        // 3. Smooth chromatic aberration (visible at 3-4MP, enhanced below 1MP, capped <= 0.1MP)
        let shiftPct = chromaticShiftPercent(for: clampedMP)
        let abberrated: CIImage
        if shiftPct > 0.0001 {
            let minShift = clampedMP <= 1.0 ? 1.8 : 1.4
            let shiftH = max(minShift, targetWidth * shiftPct)
            let shiftV = shiftH * 0.75
            abberrated = chromaticAberrationImage(softOptical, extent: targetExtent, shift: shiftH, verticalShift: shiftV)
        } else {
            abberrated = softOptical
        }
        
        // 4. Color tuning: warmer vintage tones with enriched blue in shadows & deep blacks
        let contrast = 1.16 + 0.10 * k
        let saturation = 1.10 + 0.08 * k
        let brightness = 0.03 + 0.02 * k
        let redGain = 1.05 + 0.04 * k       // Warmer golden reds
        let greenGain = 1.01 + 0.015 * k
        let blueGain = 0.96 - 0.02 * k
        let redBias = 0.018 * k            // Warm vintage ambient glow
        let blueBias = 0.038 * k           // Rich blue tint in shadows & deep blacks
        let greenBias = 0.0
        
        guard let vintageToned = colorControlledImage(
            abberrated,
            saturation: saturation,
            brightness: brightness,
            contrast: contrast
        ),
        let warmed = colorMatrixImage(
            vintageToned,
            red: redGain,
            green: greenGain,
            blue: blueGain,
            redBias: redBias,
            greenBias: greenBias,
            blueBias: blueBias
        ) else {
            return abberrated
        }
        
        // 5. Halation highlight bloom (scaled to image resolution)
        let bloomIntensity = 0.22 + 0.16 * k
        let bloomRadius = max(0.5, (3.0 + 2.0 * k) * (targetWidth / 1500.0))
        let halated = processedImage(
            named: "CIBloom",
            inputImage: warmed,
            parameters: [
                kCIInputRadiusKey: bloomRadius,
                kCIInputIntensityKey: bloomIntensity
            ]
        )?.cropped(to: targetExtent) ?? warmed
        
        // 6. Color posterization (mild, calm viewfinder contour lines)
        let posterizeLevels: Int
        if clampedMP >= 0.1 {
            posterizeLevels = max(18, min(64, Int(18.0 + (1.0 - k) * 46.0)))
        } else {
            let subT = (0.1 - clampedMP) / (0.1 - 0.01)
            posterizeLevels = max(10, Int(round(18.0 - subT * 8.0)))
        }
        let posterized = processedImage(
            named: "CIColorPosterize",
            inputImage: halated,
            parameters: ["inputLevels": posterizeLevels]
        )?.cropped(to: targetExtent) ?? halated
        
        // 7. Visible Radial Vignette (slightly stronger at 0.1MP and below)
        let vignetteIntensity = 0.72 + 0.22 * k
        let vignetted = vignetteImage(posterized, extent: targetExtent, intensity: vignetteIntensity)
        
        // 8. Dynamic Pixelation (enhanced pixelation for < 0.1MP)
        let pixScale = pixelScale(for: clampedMP)
        let pixelated: CIImage
        if pixScale > 1.05 {
            pixelated = processedImage(
                named: "CIPixellate",
                inputImage: vignetted,
                parameters: [
                    kCIInputCenterKey: CIVector(x: targetExtent.midX, y: targetExtent.midY),
                    kCIInputScaleKey: pixScale
                ]
            )?.cropped(to: targetExtent) ?? vignetted
        } else {
            pixelated = vignetted
        }
        
        // 9. Sharpness (Disabled - commented out for future use)
        let sharpened: CIImage = pixelated
        /*
        let sharpness = 0.45 + 0.35 * k
        let sharpened = sharpenedImage(pixelated, sharpness: sharpness) ?? pixelated
        */
        
        // 10. Subtle Dithering
        let ditherIntensity = 0.04 + 0.04 * k
        let dithered = processedImage(
            named: "CIDither",
            inputImage: sharpened,
            parameters: [kCIInputIntensityKey: ditherIntensity]
        )?.cropped(to: targetExtent) ?? sharpened
        
        return dithered.cropped(to: targetExtent)
    }
    
    private func pixelScale(for megaPixels: Double) -> Double {
        if megaPixels < 0.1 {
            let t = (0.1 - megaPixels) / (0.1 - 0.01)
            return 1.0 + 1.2 * t
        } else if megaPixels <= 0.3 {
            return 1.0
        } else if megaPixels <= 1.0 {
            let t = (megaPixels - 0.3) / (1.0 - 0.3)
            return 1.0 + 0.8 * t
        } else if megaPixels <= 4.0 {
            let t = (megaPixels - 1.0) / (4.0 - 1.0)
            return 1.8 + 1.2 * t
        } else {
            let t = (megaPixels - 4.0) / (12.0 - 4.0)
            return max(1.0, 3.0 - 2.0 * t)
        }
    }
    
    private func chromaticShiftPercent(for megaPixels: Double) -> Double {
        // Smooth and uniform chromatic aberration activating at <= 5.0 MP:
        // 5.0 MP -> 0.0000
        // 3.0 MP -> 0.0014
        // 1.0 MP -> 0.0020
        // <= 0.1 MP (0.1, 0.08, 0.06, 0.04, 0.02, 0.01) -> held constant at 0.0036
        if megaPixels > 5.0 {
            return 0.0
        } else if megaPixels >= 3.0 {
            let t = (5.0 - megaPixels) / (5.0 - 3.0)
            return 0.0014 * t
        } else if megaPixels >= 1.0 {
            let t = (3.0 - megaPixels) / (3.0 - 1.0)
            return 0.0014 + (0.0020 - 0.0014) * t
        } else {
            let t = (1.0 - max(0.1, megaPixels)) / (1.0 - 0.1)
            return 0.0020 + (0.0036 - 0.0020) * t
        }
    }
    
    private func retroInterpolationFactor(for megaPixels: Double) -> Double {
        let clamped = max(0.01, min(12.0, megaPixels))
        if clamped >= 0.1 {
            let minLog = log(0.1)
            let maxLog = log(12.0)
            let clampedLog = log(clamped)
            let t = (clampedLog - minLog) / (maxLog - minLog)
            return 1.0 - t
        } else {
            let t = (0.1 - clamped) / (0.1 - 0.01)
            return 1.0 + 0.35 * t
        }
    }
    
    private func chromaticAberrationImage(_ inputImage: CIImage, extent: CGRect, shift: Double = 1.2, verticalShift: Double = 1.0) -> CIImage {
        guard let redChannel = colorMatrixImage(inputImage, red: 1, green: 0, blue: 0),
              let greenChannel = colorMatrixImage(inputImage, red: 0, green: 1, blue: 0),
              let blueChannel = colorMatrixImage(inputImage, red: 0, green: 0, blue: 1) else {
            return inputImage
        }
        
        let shiftedRed = redChannel.transformed(by: CGAffineTransform(translationX: -shift, y: 0))
        let shiftedGreen = greenChannel.transformed(by: CGAffineTransform(translationX: shift, y: 0))
        let shiftedBlue = blueChannel.transformed(by: CGAffineTransform(translationX: 0, y: -verticalShift))
        
        guard let redGreen = processedImage(
            named: "CIScreenBlendMode",
            inputImage: shiftedRed,
            parameters: [kCIInputBackgroundImageKey: shiftedGreen]
        ),
        let fullRGB = processedImage(
            named: "CIScreenBlendMode",
            inputImage: shiftedBlue,
            parameters: [kCIInputBackgroundImageKey: redGreen]
        ) else {
            return inputImage
        }
        
        return fullRGB.cropped(to: extent)
    }
    
    private func vignetteImage(_ inputImage: CIImage, extent: CGRect, intensity: Double = 0.65) -> CIImage {
        let maxDim = max(extent.width, extent.height)
        let outerRadius = maxDim * 0.75
        let innerRadius = maxDim * 0.30
        let darkVal = max(0.0, 1.0 - intensity * 0.80)
        
        guard let gradient = CIFilter(name: "CIRadialGradient", parameters: [
            kCIInputCenterKey: CIVector(x: extent.midX, y: extent.midY),
            kCIInputRadius0Key: innerRadius,
            kCIInputRadius1Key: outerRadius,
            kCIInputColor0Key: CIColor(red: 1, green: 1, blue: 1, alpha: 1),
            kCIInputColor1Key: CIColor(red: darkVal, green: darkVal, blue: darkVal, alpha: 1)
        ])?.outputImage?.cropped(to: extent),
        let vignetted = processedImage(
            named: "CIMultiplyCompositing",
            inputImage: gradient,
            parameters: [kCIInputBackgroundImageKey: inputImage]
        )?.cropped(to: extent) else {
            return inputImage
        }
        return vignetted
    }
    
    private func colorControlledImage(_ inputImage: CIImage,
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
    
    private func gammaAdjustedImage(_ inputImage: CIImage, power: CGFloat) -> CIImage? {
        processedImage(
            named: "CIGammaAdjust",
            inputImage: inputImage,
            parameters: ["inputPower": power]
        )
    }
    
    private func toneCurveImage(_ inputImage: CIImage,
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
    
    private func vibranceImage(_ inputImage: CIImage, amount: CGFloat) -> CIImage? {
        processedImage(
            named: "CIVibrance",
            inputImage: inputImage,
            parameters: ["inputAmount": amount]
        )
    }
    
    private func colorMatrixImage(_ inputImage: CIImage,
                                  red: CGFloat,
                                  green: CGFloat,
                                  blue: CGFloat,
                                  redBias: CGFloat = 0,
                                  greenBias: CGFloat = 0,
                                  blueBias: CGFloat = 0) -> CIImage? {
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
    
    private func sharpenedImage(_ inputImage: CIImage, sharpness: CGFloat) -> CIImage? {
        processedImage(
            named: "CISharpenLuminance",
            inputImage: inputImage,
            parameters: [kCIInputSharpnessKey: sharpness]
        )
    }
    
    private func processedImage(named filterName: String,
                                inputImage: CIImage,
                                parameters: [String: Any] = [:]) -> CIImage? {
        guard let filter = CIFilter(name: filterName) else { return nil }
        filter.setValue(inputImage, forKey: kCIInputImageKey)
        for (key, value) in parameters {
            filter.setValue(value, forKey: key)
        }
        return filter.outputImage
    }
}
