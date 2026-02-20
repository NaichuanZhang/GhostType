import SwiftUI

/// A simple animated ghost avatar for the AI assistant.
/// Displayed alongside AI responses in the floating panel.
struct AvatarView: View {
    var size: CGFloat = 28
    var isAnimating: Bool = false

    @State private var bobOffset: CGFloat = 0

    var body: some View {
        ZStack {
            // Glow background
            Circle()
                .fill(.purple.opacity(0.15))
                .frame(width: size + 4, height: size + 4)

            // Ghost body
            GhostShape()
                .fill(
                    LinearGradient(
                        colors: [.purple.opacity(0.9), .purple.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 0.7, height: size * 0.75)
                .offset(y: bobOffset)

            // Eyes
            HStack(spacing: size * 0.1) {
                Circle()
                    .fill(.white)
                    .frame(width: size * 0.13, height: size * 0.13)
                Circle()
                    .fill(.white)
                    .frame(width: size * 0.13, height: size * 0.13)
            }
            .offset(y: -size * 0.05 + bobOffset)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard isAnimating else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                bobOffset = -2
            }
        }
        .onChange(of: isAnimating) { animating in
            if animating {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    bobOffset = -2
                }
            } else {
                withAnimation(.easeInOut(duration: 0.3)) {
                    bobOffset = 0
                }
            }
        }
    }
}

/// Custom ghost shape — rounded top with wavy bottom edge.
struct GhostShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        // Start at bottom-left
        path.move(to: CGPoint(x: 0, y: h))

        // Wavy bottom: 3 bumps
        let bumpW = w / 3
        path.addQuadCurve(
            to: CGPoint(x: bumpW, y: h * 0.85),
            control: CGPoint(x: bumpW * 0.5, y: h * 0.7)
        )
        path.addQuadCurve(
            to: CGPoint(x: bumpW * 2, y: h),
            control: CGPoint(x: bumpW * 1.5, y: h * 1.1)
        )
        path.addQuadCurve(
            to: CGPoint(x: w, y: h * 0.85),
            control: CGPoint(x: bumpW * 2.5, y: h * 0.7)
        )

        // Right side up
        path.addLine(to: CGPoint(x: w, y: h * 0.4))

        // Rounded top (dome)
        path.addCurve(
            to: CGPoint(x: 0, y: h * 0.4),
            control1: CGPoint(x: w, y: -h * 0.1),
            control2: CGPoint(x: 0, y: -h * 0.1)
        )

        // Left side down
        path.closeSubpath()
        return path
    }
}
