import CoreImage
import Foundation

struct PhotoFilterLiveRenderer {
    func filteredImage(from sourceImage: CIImage, filter: PhotoFilter, referenceSize: CGSize) -> CIImage? {
        let previewScale = previewScale(for: sourceImage.extent, referenceSize: referenceSize)
        
        return switch filter {
            case .off:
                sourceImage
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
