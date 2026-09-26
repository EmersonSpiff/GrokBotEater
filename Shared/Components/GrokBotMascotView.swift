import SwiftUI

struct GrokBotMascotView: View {
    let size: CGFloat
    let tint: Color
    let animated: Bool
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    private let eyeHalfWidth: CGFloat = 21.0
    private let eyeHalfHeight: CGFloat = 5.0
    
    var body: some View {
        TimelineView(.animation(minimumInterval: animated && !reduceMotion ? 1.0/30.0 : nil, paused: !animated || reduceMotion)) { context in
            drawContent(time: context.date.timeIntervalSinceReferenceDate)
        }
    }
    
    private func drawContent(time: TimeInterval) -> some View {
        Canvas { ctx, canvasSize in
            let scale = size / 228.541
            let centerX = size / 2
            let centerY = size / 2
            
            var blobTransform = CGAffineTransform(scaleX: scale, y: scale)
            
            if animated && !reduceMotion {
                let wobble = sin(time * 0.8) * 1.5
                blobTransform = blobTransform.rotated(by: wobble * .pi / 180)
            }
            
            let blobCGPath = createBlobPath()
            let transformedBlob = blobCGPath.copy(using: &blobTransform)
            let blobBounds = transformedBlob?.boundingBox ?? .zero
            let offsetX = centerX - blobBounds.midX
            let offsetY = centerY - blobBounds.midY
            
            ctx.translateBy(x: offsetX, y: offsetY)
            
            if let path = transformedBlob {
                ctx.fill(Path(path), with: .color(tint.opacity(0.88)))
                
                let highlightColor = tint.opacity(0.3)
                ctx.fill(Path(path), with: .color(highlightColor))
            }
            
            let blinkScale = computeBlinkScale(time: time)
            
            if animated && !reduceMotion {
                let gazeX = sin(time * 0.4) * size * 0.03
                let gazeY = cos(time * 0.3) * size * 0.02
                
                drawEye(
                    in: ctx,
                    center: CGPoint(
                        x: centerX - size * 0.18 + gazeX + offsetX,
                        y: centerY - size * 0.06 + gazeY + offsetY
                    ),
                    width: eyeHalfWidth * scale,
                    height: eyeHalfHeight * scale * blinkScale,
                    rotation: -15.0
                )
                
                drawEye(
                    in: ctx,
                    center: CGPoint(
                        x: centerX + size * 0.18 + gazeX + offsetX,
                        y: centerY - size * 0.06 + gazeY + offsetY
                    ),
                    width: eyeHalfWidth * scale,
                    height: eyeHalfHeight * scale * blinkScale,
                    rotation: 15.0
                )
            } else {
                drawEye(
                    in: ctx,
                    center: CGPoint(
                        x: centerX - size * 0.18 + offsetX,
                        y: centerY - size * 0.06 + offsetY
                    ),
                    width: eyeHalfWidth * scale,
                    height: eyeHalfHeight * scale,
                    rotation: -15.0
                )
                
                drawEye(
                    in: ctx,
                    center: CGPoint(
                        x: centerX + size * 0.18 + offsetX,
                        y: centerY - size * 0.06 + offsetY
                    ),
                    width: eyeHalfWidth * scale,
                    height: eyeHalfHeight * scale,
                    rotation: 15.0
                )
            }
        }
        .frame(width: size, height: size)
    }
    
    private func computeBlinkScale(time: TimeInterval) -> CGFloat {
        guard animated && !reduceMotion else { return 1.0 }
        
        let slotDuration: TimeInterval = 3.5
        let blinkDuration: TimeInterval = 0.15
        
        let slotIndex = Int(time / slotDuration)
        let timeInSlot = time.truncatingRemainder(dividingBy: slotDuration)
        
        let hash = (slotIndex &* 2654435761) & 0x7FFFFFFF
        let slotLength = 2.0 + Double(hash % 3000) / 1000.0
        
        if timeInSlot > slotLength {
            return 1.0
        }
        
        if timeInSlot < blinkDuration {
            let progress = timeInSlot / blinkDuration
            if progress < 0.5 {
                let easeDown = 1.0 - (progress * 2.0) * (progress * 2.0)
                return 1.0 - 0.9 * easeDown
            } else {
                let easeUp = (progress - 0.5) * 2.0
                return 0.1 + 0.9 * easeUp * easeUp
            }
        }
        
        return 1.0
    }
    
    private func createBlobPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 228.541, y: 114.228))
        path.addCurve(to: CGPoint(x: 218.738, y: 160.534), control1: CGPoint(x: 228.541, y: 130.133), control2: CGPoint(x: 225.184, y: 145.994))
        path.addCurve(to: CGPoint(x: 193.065, y: 196.988), control1: CGPoint(x: 212.674, y: 174.217), control2: CGPoint(x: 203.904, y: 186.669))
        path.addCurve(to: CGPoint(x: 55.5255, y: 212.24), control1: CGPoint(x: 155.933, y: 232.34), control2: CGPoint(x: 99.497, y: 238.596))
        path.addCurve(to: CGPoint(x: 27.7451, y: 188.866), control1: CGPoint(x: 45.097, y: 205.99), control2: CGPoint(x: 35.6851, y: 198.072))
        path.addCurve(to: CGPoint(x: 7.65781, y: 155.351), control1: CGPoint(x: 19.1926, y: 178.953), control2: CGPoint(x: 12.3686, y: 167.569))
        path.addCurve(to: CGPoint(x: 0, y: 114.228), control1: CGPoint(x: 2.60712, y: 142.264), control2: CGPoint(x: 0, y: 128.257))
        path.addCurve(to: CGPoint(x: 9.80315, y: 67.9215), control1: CGPoint(x: 0, y: 98.3219), control2: CGPoint(x: 3.35751, y: 82.4611))
        path.addCurve(to: CGPoint(x: 35.4767, y: 31.4668), control1: CGPoint(x: 15.8672, y: 54.2382), control2: CGPoint(x: 24.6377, y: 41.7862))
        path.addCurve(to: CGPoint(x: 173.016, y: 16.2153), control1: CGPoint(x: 72.6081, y: -3.88483), control2: CGPoint(x: 129.044, y: -10.1413))
        path.addCurve(to: CGPoint(x: 200.796, y: 39.5896), control1: CGPoint(x: 183.444, y: 22.4653), control2: CGPoint(x: 192.856, y: 30.3829))
        path.addCurve(to: CGPoint(x: 220.883, y: 73.1037), control1: CGPoint(x: 209.349, y: 49.5018), control2: CGPoint(x: 216.173, y: 60.8859))
        path.addCurve(to: CGPoint(x: 228.541, y: 114.228), control1: CGPoint(x: 225.934, y: 86.1906), control2: CGPoint(x: 228.541, y: 100.198))
        path.closeSubpath()
        return path
    }
    
    private func drawEye(in context: GraphicsContext, center: CGPoint, width: CGFloat, height: CGFloat, rotation: Double) {
        var eyePath = Path()
        eyePath.addEllipse(in: CGRect(
            x: center.x - width,
            y: center.y - height,
            width: width * 2,
            height: height * 2
        ))
        
        let rotationRadians = rotation * .pi / 180
        let rotationTransform = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: rotationRadians)
            .translatedBy(x: -center.x, y: -center.y)
        
        eyePath = eyePath.applying(rotationTransform)
        context.fill(eyePath, with: .color(.black))
    }
}
