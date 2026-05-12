internal import AVFoundation
import Foundation

enum Lens: String, CaseIterable {
    case frontUltraWide, front, ultraWide, wide, tele2x, tele4x, tele8x
    
    var label: String {
        switch self {
            case .frontUltraWide: "1"
            case .front: "1.5"
            case .ultraWide: "0.5"
            case .wide: "1"
            case .tele2x: "2"
            case .tele4x: "4"
            case .tele8x: "8"
        }
    }
    
    nonisolated var isFront: Bool { self == .front || self == .frontUltraWide }
    
    var deviceType: AVCaptureDevice.DeviceType {
        switch self {
            case .front, .frontUltraWide: .builtInUltraWideCamera
            case .ultraWide: .builtInUltraWideCamera
            case .wide, .tele2x: .builtInWideAngleCamera
            case .tele4x, .tele8x: .builtInTelephotoCamera
        }
    }
    
    var preferredDeviceTypes: [AVCaptureDevice.DeviceType] {
        switch self {
            case .frontUltraWide:
                [.builtInUltraWideCamera, .builtInTrueDepthCamera, .builtInWideAngleCamera]
            case .front:
                [.builtInUltraWideCamera, .builtInTrueDepthCamera, .builtInWideAngleCamera]
            case .ultraWide:
                [.builtInUltraWideCamera]
            case .wide, .tele2x:
                [.builtInWideAngleCamera]
            case .tele4x, .tele8x:
                [.builtInTelephotoCamera]
        }
    }
    
    var position: AVCaptureDevice.Position { isFront ? .front : .back }
    
    var zoomFactor: CGFloat {
        switch self {
            case .tele2x: 2.0
            case .tele8x: 2.0
            case .front: 1.55
            default: 1.0
        }
    }
    
    var preservesRawCaptureMode: Bool {
        switch self {
            case .frontUltraWide, .ultraWide, .wide, .tele4x:
                true
            default:
                false
        }
    }
    
    var preservesHighResolutionCapture: Bool {
        switch self {
            case .ultraWide, .wide, .tele4x:
                true
            default:
                false
        }
    }
    
    var rawFallbackLens: Lens {
        switch self {
            case .front:
                    .frontUltraWide
            case .tele2x:
                    .wide
            case .tele8x:
                    .tele4x
            default:
                self
        }
    }
    
    var highResolutionFallbackLens: Lens {
        switch self {
            case .tele2x:
                    .wide
            case .tele8x:
                    .tele4x
            default:
                self
        }
    }
    
    func captureDevice() -> AVCaptureDevice? {
        for deviceType in preferredDeviceTypes {
            if let device = AVCaptureDevice.default(deviceType, for: .video, position: position) {
                return device
            }
        }
        
        let matchedDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: preferredDeviceTypes,
            mediaType: .video,
            position: position
        ).devices
        if let device = matchedDevices.first {
            return device
        }
        
        guard self == .wide else { return nil }
        return Self.bestGeneralPurposeCamera(allowFront: false)
    }
    
    static func initialCaptureDevice() -> (lens: Lens, device: AVCaptureDevice)? {
        if !hasMultipleVideoDevices, let device = bestGeneralPurposeCamera(allowFront: true) {
            return (.wide, device)
        }
        
        for lens in [Lens.wide, .front, .frontUltraWide, .ultraWide, .tele4x] {
            if let device = lens.captureDevice() {
                let resolvedLens: Lens = device.position == .front ? .front : lens
                return (resolvedLens, device)
            }
        }
        
        guard let device = bestGeneralPurposeCamera(allowFront: true) else { return nil }
        return (device.position == .front ? .front : .wide, device)
    }
    
    static func supportsAlternateFacing(from lens: Lens) -> Bool {
        guard hasMultipleVideoDevices else { return false }
        
        if lens.isFront {
            return Lens.wide.captureDevice() != nil
        }
        
        return Lens.front.captureDevice() != nil || Lens.frontUltraWide.captureDevice() != nil
    }
    
    static func captureDevice(uniqueID: String) -> AVCaptureDevice? {
        return availableVideoDevices.first(where: { $0.uniqueID == uniqueID })
    }
    
    nonisolated static func rotationAngle(for device: AVCaptureDevice, lens: Lens) -> CGFloat {
        if device.isContinuityCamera || device.deviceType == .external || device.position == .unspecified {
            return 0
        }
        
        return lens.isFront ? 0 : 90
    }
    
    nonisolated static func isMirrored(_ device: AVCaptureDevice, lens: Lens) -> Bool {
        return lens.isFront && hasMultipleVideoDevices
    }
    
    nonisolated static var hasMultipleVideoDevices: Bool {
        availableVideoDevices.count > 1
    }
    
    private static func bestGeneralPurposeCamera(allowFront: Bool) -> AVCaptureDevice? {
        let devices = availableVideoDevices.filter { allowFront || $0.position != .front }
        
        return devices.first(where: { !$0.isSuspended }) ?? devices.first
    }
    
    private nonisolated static var availableVideoDevices: [AVCaptureDevice] {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: generalPurposeDeviceTypes,
            mediaType: .video,
            position: .unspecified
        ).devices
        
        var seenIDs: Set<String> = []
        return devices.filter { device in
            guard !seenIDs.contains(device.uniqueID) else { return false }
            seenIDs.insert(device.uniqueID)
            return true
        }
    }
    
    private nonisolated static var generalPurposeDeviceTypes: [AVCaptureDevice.DeviceType] {
        [
            .builtInWideAngleCamera,
            .builtInTrueDepthCamera,
            .builtInUltraWideCamera,
            .builtInTelephotoCamera,
            .continuityCamera,
            .external
        ]
    }
}
