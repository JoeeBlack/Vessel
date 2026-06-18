import SwiftUI

struct StatusIndicator: View {
    let status: VesselStatus
    var size: CGFloat = 6

    var color: Color {
        switch status {
        case .running: return AppTheme.runningGreen
        case .stopped: return AppTheme.stoppedRed
        case .paused: return .yellow
        case .creating, .starting: return .orange
        case .error: return .red
        case .unknown: return .gray
        }
    }

    struct AnimationValues {
        var scale: Double = 1.0
        var opacity: Double = 1.0
        var colorOpacity: Double = 1.0
    }

    var body: some View {
        let resolvedColor = self.color

        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .keyframeAnimator(
                initialValue: AnimationValues(),
                repeating: status == .running || status == .paused
            ) { content, value in
                content
                    .scaleEffect(value.scale)
                    .opacity(value.opacity)
                    .overlay(
                        Circle()
                            .fill(resolvedColor.opacity(value.colorOpacity))
                            .scaleEffect(value.scale * 1.5)
                    )
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    CubicKeyframe(1.0, duration: 0.2)
                    CubicKeyframe(1.3, duration: 0.6)
                    CubicKeyframe(1.0, duration: 0.4)
                }
                KeyframeTrack(\.opacity) {
                    CubicKeyframe(1.0, duration: 0.2)
                    CubicKeyframe(0.8, duration: 0.6)
                    CubicKeyframe(1.0, duration: 0.4)
                }
                KeyframeTrack(\.colorOpacity) {
                    CubicKeyframe(0.0, duration: 0.2)
                    CubicKeyframe(0.4, duration: 0.4)
                    CubicKeyframe(0.0, duration: 0.6)
                }
            }
    }
}
