import CoreGraphics
import Foundation

public enum OverlayResizeHandle: String, CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    public var anchor: CGPoint {
        switch self {
        case .topLeft: CGPoint(x:0,y:0); case .top: CGPoint(x:0.5,y:0); case .topRight: CGPoint(x:1,y:0)
        case .right: CGPoint(x:1,y:0.5); case .bottomRight: CGPoint(x:1,y:1); case .bottom: CGPoint(x:0.5,y:1)
        case .bottomLeft: CGPoint(x:0,y:1); case .left: CGPoint(x:0,y:0.5)
        }
    }
}
/// Normalized, top-left final-output bounds, matching PrivacyMask and Annotation.
public struct OverlayBounds: Sendable, Equatable {
    public var x: Double; public var y: Double; public var width: Double; public var height: Double; public var rotation: Double
    public init(x: Double, y: Double, width: Double, height: Double, rotation: Double = 0) {
        self.x=x;self.y=y;self.width=width;self.height=height;self.rotation=rotation
    }
}
public enum OverlayGeometry {
    /// Translation/viewport are in the same display units. Output stays normalized;
    /// the ungrabbed edge stays fixed before boundary clamping, including rotated areas.
    public static func resized(_ original: OverlayBounds, handle: OverlayResizeHandle, translation: CGSize, viewport: CGSize, preserveAspect: Bool = false) -> OverlayBounds {
        guard viewport.width.isFinite, viewport.height.isFinite, viewport.width > 0, viewport.height > 0,
              translation.width.isFinite, translation.height.isFinite,
              [original.x,original.y,original.width,original.height,original.rotation].allSatisfy(\.isFinite),
              original.width > 0, original.height > 0
        else { return original }
        let angle=original.rotation * .pi/180, c=cos(angle), s=sin(angle)
        let dx=(c*translation.width+s*translation.height)/viewport.width
        let dy=(-s*translation.width+c*translation.height)/viewport.height
        let anchor=handle.anchor
        var w=original.width, h=original.height, cx=0.0, cy=0.0
        if anchor.x == 0 { w=min(1,max(0.01,original.width-dx));cx=(original.width-w)*viewport.width/2 }
        if anchor.x == 1 { w=min(1,max(0.01,original.width+dx));cx=(w-original.width)*viewport.width/2 }
        if anchor.y == 0 { h=min(1,max(0.01,original.height-dy));cy=(original.height-h)*viewport.height/2 }
        if anchor.y == 1 { h=min(1,max(0.01,original.height+dy));cy=(h-original.height)*viewport.height/2 }
        if preserveAspect {
            // Project corner motion onto the original diagonal rather than choosing a
            // fluctuating dominant axis. Edge handles scale around the opposite midpoint.
            let sx = anchor.x == 0 ? -1.0 : anchor.x == 1 ? 1.0 : 0.0
            let sy = anchor.y == 0 ? -1.0 : anchor.y == 1 ? 1.0 : 0.0
            let vx = sx * original.width * viewport.width
            let vy = sy * original.height * viewport.height
            let localX = dx * viewport.width, localY = dy * viewport.height
            let denominator = vx * vx + vy * vy
            guard denominator > 0 else { return original }
            let requested = 1 + (localX * vx + localY * vy) / denominator
            let scale = min(min(1 / original.width, 1 / original.height),
                            max(max(0.01 / original.width, 0.01 / original.height), requested))
            w = original.width * scale; h = original.height * scale
            cx = sx * (w - original.width) * viewport.width / 2
            cy = sy * (h - original.height) * viewport.height / 2
        }
        let centreX=original.x+original.width/2+(c*cx-s*cy)/viewport.width
        let centreY=original.y+original.height/2+(s*cx+c*cy)/viewport.height
        return OverlayBounds(x:min(1-w,max(0,centreX-w/2)),y:min(1-h,max(0,centreY-h/2)),width:w,height:h,rotation:original.rotation)
    }
}

extension OverlayGeometry {
    /// Clockwise display rotation around the selected area's centre. Pointer positions
    /// share the viewport's units; scale and display resolution do not affect the result.
    public static func rotated(_ original: OverlayBounds, from start: CGPoint, to point: CGPoint, viewport: CGSize) -> OverlayBounds {
        guard viewport.width > 0, viewport.height > 0,
              [Double(start.x),Double(start.y),Double(point.x),Double(point.y),Double(viewport.width),Double(viewport.height),original.rotation].allSatisfy(\.isFinite)
        else { return original }
        let cx=(original.x+original.width/2)*viewport.width, cy=(original.y+original.height/2)*viewport.height
        let sx=Double(start.x-cx), sy=Double(start.y-cy), px=Double(point.x-cx), py=Double(point.y-cy)
        guard hypot(sx,sy)>0.001, hypot(px,py)>0.001 else { return original }
        var result=original
        let angle=original.rotation+(atan2(py,px)-atan2(sy,sx))*180 / .pi
        result.rotation=((angle+180).truncatingRemainder(dividingBy:360)+360).truncatingRemainder(dividingBy:360)-180
        return result
    }
}
