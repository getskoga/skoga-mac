import SwiftUI
import Foundation

extension Color {
    /// OKLCH → sRGB using Björn Ottosson's transform. L in [0,1], C ~[0, 0.4], h in degrees.
    /// Out-of-gamut values are clipped per-channel to [0,1]; this matches what browsers do
    /// for the design's parchment palette where none of the tokens hit the boundary.
    static func oklch(_ l: Double, _ c: Double, _ h: Double, opacity: Double = 1.0) -> Color {
        let hRad = h * .pi / 180.0
        let a = c * cos(hRad)
        let b = c * sin(hRad)

        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b

        let lc = l_ * l_ * l_
        let mc = m_ * m_ * m_
        let sc = s_ * s_ * s_

        let rLin =  4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc
        let gLin = -1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc
        let bLin = -0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc

        return Color(
            .sRGB,
            red:     gammaEncode(rLin),
            green:   gammaEncode(gLin),
            blue:    gammaEncode(bLin),
            opacity: opacity
        )
    }

    private static func gammaEncode(_ c: Double) -> Double {
        let clipped = max(0.0, min(1.0, c))
        if clipped >= 0.0031308 {
            return 1.055 * pow(clipped, 1.0 / 2.4) - 0.055
        } else {
            return 12.92 * clipped
        }
    }
}
