import CoreGraphics

enum DualCameraPipPlacement: String, Sendable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
    
    nonisolated var isLeading: Bool {
        switch self {
            case .topLeading, .bottomLeading: true
            case .topTrailing, .bottomTrailing: false
        }
    }
    
    nonisolated var isTop: Bool {
        switch self {
            case .topLeading, .topTrailing: true
            case .bottomLeading, .bottomTrailing: false
        }
    }
    
    nonisolated func moved(by translation: CGSize, threshold: CGFloat) -> DualCameraPipPlacement {
        let nextIsLeading = abs(translation.width) >= threshold ? translation.width < 0 : isLeading
        let nextIsTop = abs(translation.height) >= threshold ? translation.height < 0 : isTop
        return Self.placement(isTop: nextIsTop, isLeading: nextIsLeading)
    }
    
    nonisolated func previewRect(in canvasSize: CGSize, pipSize: CGSize, inset: CGFloat) -> CGRect {
        CGRect(
            x: isLeading ? inset : canvasSize.width - pipSize.width - inset,
            y: isTop ? inset : canvasSize.height - pipSize.height - inset,
            width: pipSize.width,
            height: pipSize.height
        )
    }
    
    nonisolated func photoRect(in canvasSize: CGSize, pipSize: CGSize, inset: CGFloat) -> CGRect {
        CGRect(
            x: isLeading ? inset : canvasSize.width - pipSize.width - inset,
            y: isTop ? canvasSize.height - pipSize.height - inset : inset,
            width: pipSize.width,
            height: pipSize.height
        )
    }
    
    nonisolated var opposite: DualCameraPipPlacement {
        Self.placement(isTop: !isTop, isLeading: !isLeading)
    }
    
    nonisolated var rotatedClockwise: DualCameraPipPlacement {
        switch self {
            case .topLeading: .topTrailing
            case .topTrailing: .bottomTrailing
            case .bottomTrailing: .bottomLeading
            case .bottomLeading: .topLeading
        }
    }
    
    nonisolated var rotatedCounterclockwise: DualCameraPipPlacement {
        switch self {
            case .topLeading: .bottomLeading
            case .bottomLeading: .bottomTrailing
            case .bottomTrailing: .topTrailing
            case .topTrailing: .topLeading
        }
    }
    
    private nonisolated static func placement(isTop: Bool, isLeading: Bool) -> DualCameraPipPlacement {
        switch (isTop, isLeading) {
            case (true, true): .topLeading
            case (true, false): .topTrailing
            case (false, true): .bottomLeading
            case (false, false): .bottomTrailing
        }
    }
}
