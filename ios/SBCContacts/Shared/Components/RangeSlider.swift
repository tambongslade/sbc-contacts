import SwiftUI

/// Two-thumb slider over whole numbers — Flutter's `RangeSlider`.
///
/// The track is inset by `trackInset` on each side, and thumb centres travel
/// exactly over that track, so anything drawn above it (age badges) can place
/// itself with `RangeSlider.centerX(...)` and land on the thumbs by construction.
struct RangeSlider: View {
    @Binding var lower: Double
    @Binding var upper: Double
    let bounds: ClosedRange<Double>
    var step: Double = 1
    var trackHeight: CGFloat = 4
    var activeColor: Color = SBCColors.primary
    var inactiveColor: Color = Color(.systemFill)
    /// White with a soft shadow, like the system `Slider` knob.
    var thumbColor: Color = .white
    var onChange: () -> Void = {}

    static let trackInset: CGFloat = 16
    private let thumbDiameter: CGFloat = 28

    /// Horizontal centre of the thumb for `value` in a slider `width` wide.
    static func centerX(for value: Double, in bounds: ClosedRange<Double>, width: CGFloat) -> CGFloat {
        let ratio = (value - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound)
        return trackInset + CGFloat(ratio) * (width - trackInset * 2)
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let lowX = Self.centerX(for: lower, in: bounds, width: width)
            let highX = Self.centerX(for: upper, in: bounds, width: width)
            let midY = geo.size.height / 2

            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(inactiveColor)
                    .frame(width: width - Self.trackInset * 2, height: trackHeight)
                    .position(x: width / 2, y: midY)
                Capsule()
                    .fill(activeColor)
                    .frame(width: max(highX - lowX, 0), height: trackHeight)
                    .position(x: (lowX + highX) / 2, y: midY)

                thumb
                    .position(x: lowX, y: midY)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                        lower = min(value(at: g.location.x, width: width), upper)
                        onChange()
                    })
                    .accessibilityElement()
                    .accessibilityLabel("Minimum")
                    .accessibilityValue("\(Int(lower))")
                    .accessibilityAdjustableAction { direction in
                        lower = direction == .increment ? min(lower + step, upper) : max(lower - step, bounds.lowerBound)
                        onChange()
                    }

                thumb
                    .position(x: highX, y: midY)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                        upper = max(value(at: g.location.x, width: width), lower)
                        onChange()
                    })
                    .accessibilityElement()
                    .accessibilityLabel("Maximum")
                    .accessibilityValue("\(Int(upper))")
                    .accessibilityAdjustableAction { direction in
                        upper = direction == .increment ? min(upper + step, bounds.upperBound) : max(upper - step, lower)
                        onChange()
                    }
            }
        }
        .frame(height: 44)
    }

    private var thumb: some View {
        Circle()
            .fill(thumbColor)
            .frame(width: thumbDiameter, height: thumbDiameter)
            .shadow(color: .black.opacity(0.12), radius: 0.5, y: 0)
            .shadow(color: .black.opacity(0.15), radius: 4, y: 3)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    private func value(at x: CGFloat, width: CGFloat) -> Double {
        let fraction = min(max(Double((x - Self.trackInset) / (width - Self.trackInset * 2)), 0), 1)
        let raw = bounds.lowerBound + fraction * (bounds.upperBound - bounds.lowerBound)
        return (raw / step).rounded() * step
    }
}
