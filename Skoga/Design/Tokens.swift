import SwiftUI
import Foundation

/// Layout primitives — sizes, radii, hairlines. Kept tiny so views read like the design CSS.
enum Tokens {
    static let titlebarHeight: CGFloat = 44
    static let sidebarWidth: CGFloat = 224
    static let convAsideWidth: CGFloat = 320
    static let dispatchAsideWidth: CGFloat = 320

    enum Radius {
        static let chip: CGFloat = 6
        static let card: CGFloat = 10
        static let modal: CGFloat = 12
        static let pill: CGFloat = 999
        static let input: CGFloat = 8
        static let tiny: CGFloat = 3
    }

    enum Hairline {
        /// 0.5pt hairline — matches the CSS `0.5px` rules.
        static let width: CGFloat = 0.5
    }

    enum Pad {
        static let viewX: CGFloat = 22
        static let viewY: CGFloat = 18
        static let sidebarX: CGFloat = 16
        static let cardX: CGFloat = 14
        static let cardY: CGFloat = 14
    }
}

// MARK: – Hairline divider

struct Hairline: View {
    @Environment(\.palette) private var p
    var axis: Axis = .horizontal
    var color: Color? = nil
    var hard: Bool = false

    var body: some View {
        let c = color ?? (hard ? p.ruleHard : p.rule)
        Rectangle()
            .fill(c)
            .frame(
                width:  axis == .vertical ? Tokens.Hairline.width : nil,
                height: axis == .horizontal ? Tokens.Hairline.width : nil
            )
    }
}

// MARK: – Hairline stroke modifier (for borders)

extension View {
    func hairlineBorder(_ color: Color, radius: CGFloat = 0) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(color, lineWidth: Tokens.Hairline.width)
        )
    }
}
