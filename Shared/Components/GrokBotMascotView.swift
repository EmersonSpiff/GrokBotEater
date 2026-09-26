import SwiftUI

struct GrokBotMascotView: View {
    let size: CGFloat
    let tint: Color
    let animated: Bool
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blinkPhase: Double = 0.0
    @State private var gazeOffset: CGSize = .zero
    @State private var wobbleAngle: Double = 0.0
    @State private var timer: Timer? = nil
    @State private var nextBlinkTime: TimeInterval = 0.0
    
    private let blobPath = "M228.541 114.228C228.541 130.133 225.184 145.994 218.738 160.534C212.674 174.217 203.904 186.669 193.065 196.988C155.933 232.34 99.497 238.596 55.5255 212.24C45.097 205.99 35.6851 198.072 27.7451 188.866C19.1926 178.953 12.3686 167.569 7.65781 155.351C2.60712 142.264 0 128.257 0 114.228C0 98.3219 3.35751 82.4611 9.80315 67.9215C15.8672 54.2382 24.6377 41.7862 35.4767 31.4668C72.6081 -3.88483 129.044 -10.1413 173.016 16.2153C183.444 22.4653 192.856 30.3829 200.796 39.5896C209.349 49.5018 216.173 60.8859 220.883 73.1037C225.934 86.1906 228.541 100.198 228.541 114.228Z"
    
    private let eyeHalfWidth: CGFloat = 21.0
    private let eyeHalfHeight: CGFloat = 5.0
    
    var body: some View {
        TimelineView(.animation(minimumInterval: animated && !reduceMotion ? 1.0/30.0 : nil, paused: !animated || reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            
            Canvas { ctx, canvasSize in
                let scale = size / 228.541
                let centerX = size / 2
                let centerY = size / 2
                
                var blobTransform = CGAffineTransform(scaleX: scale, y: scale)
                
                if animated && !reduceMotion {
                    let wobble = sin(time * 0.8) * 1.5
                    blobTransform = blobTransform.rotated(by: wobble * .pi / 180)
                }
                
                if let blobCGPath = CGPath.from(svgPath: blobPath) {
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
                }
                
                if animated && !reduceMotion {
                    let gazeX = sin(time * 0.4) * size * 0.03
                    let gazeY = cos(time * 0.3) * size * 0.02
                    
                    let blinkCycle = sin(time * 0.5) > 0.95 ? 0.1 : 1.0
                    
                    drawEye(
                        in: ctx,
                        center: CGPoint(
                            x: centerX - size * 0.18 + gazeX + offsetX,
                            y: centerY - size * 0.06 + gazeY + offsetY
                        ),
                        width: eyeHalfWidth * scale,
                        height: eyeHalfHeight * scale * blinkCycle,
                        rotation: -15.0
                    )
                    
                    drawEye(
                        in: ctx,
                        center: CGPoint(
                            x: centerX + size * 0.18 + gazeX + offsetX,
                            y: centerY - size * 0.06 + gazeY + offsetY
                        ),
                        width: eyeHalfWidth * scale,
                        height: eyeHalfHeight * scale * blinkCycle,
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

extension CGPath {
    static func from(svgPath: String) -> CGPath? {
        let path = CGMutablePath()
        
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var controlX1: CGFloat = 0
        var controlY1: CGFloat = 0
        var controlX2: CGFloat = 0
        var controlY2: CGFloat = 0
        
        let scanner = Scanner(string: svgPath)
        scanner.charactersToBeSkipped = CharacterSet.whitespacesAndNewlines
        
        while !scanner.isAtEnd {
            var command: String = ""
            if scanner.scanCharacters(from: CharacterSet.letters, into: &command) {
                switch command {
                case "M":
                    if let x = scanner.scanDouble(), let y = scanner.scanDouble() {
                        path.move(to: CGPoint(x: x, y: y))
                        currentX = x
                        currentY = y
                    }
                case "C":
                    while let x1 = scanner.scanDouble(),
                          let y1 = scanner.scanDouble(),
                          let x2 = scanner.scanDouble(),
                          let y2 = scanner.scanDouble(),
                          let x = scanner.scanDouble(),
                          let y = scanner.scanDouble() {
                        path.addCurve(
                            to: CGPoint(x: x, y: y),
                            control1: CGPoint(x: x1, y: y1),
                            control2: CGPoint(x: x2, y: y2)
                        )
                        controlX1 = x1
                        controlY1 = y1
                        controlX2 = x2
                        controlY2 = y2
                        currentX = x
                        currentY = y
                        
                        if scanner.scanString("C", into: nil) {
                            continue
                        } else {
                            break
                        }
                    }
                case "Z":
                    path.closeSubpath()
                default:
                    break
                }
            }
            
            scanner.scanCharacters(from: CharacterSet(charactersIn: ","), into: nil)
        }
        
        return path
    }
}

extension Scanner {
    func scanDouble() -> CGFloat? {
        var value: Double = 0
        if scanDouble(&value) {
            return CGFloat(value)
        }
        return nil
    }
}
