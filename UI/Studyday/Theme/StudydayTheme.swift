import SwiftUI

/// Tokens extracted from the Studyday MHTML mockup (Expo / react-native-web).
enum StudydayTheme {
    /// Near-black ink used for brand, headlines, and primary CTA.
    static let ink = Color(red: 25 / 255, green: 27 / 255, blue: 29 / 255)
    /// Soft sage-gray for badges / secondary labels.
    static let sage = Color(red: 112 / 255, green: 131 / 255, blue: 123 / 255)
    /// Muted body copy.
    static let muted = Color(red: 112 / 255, green: 117 / 255, blue: 120 / 255)
    /// Brand blue accent (dot, badge pip, interactive).
    static let accent = Color(red: 67 / 255, green: 136 / 255, blue: 237 / 255)
    static let accentBright = Color(red: 84 / 255, green: 141 / 255, blue: 244 / 255)
    /// Soft blue-gray icon wells.
    static let mist = Color(red: 237 / 255, green: 242 / 255, blue: 246 / 255)
    static let mistDeep = Color(red: 236 / 255, green: 241 / 255, blue: 247 / 255)
    /// Soft green check / success accent from preview card.
    static let softGreen = Color(red: 107 / 255, green: 147 / 255, blue: 131 / 255)
    static let iconBlue = Color(red: 82 / 255, green: 124 / 255, blue: 158 / 255)
    /// Paper surfaces.
    static let paper = Color(red: 250 / 255, green: 250 / 255, blue: 248 / 255)
    static let paperElevated = Color.white
    static let chipFill = Color(red: 240 / 255, green: 241 / 255, blue: 239 / 255)
    static let outerWash = Color(red: 233 / 255, green: 236 / 255, blue: 235 / 255)
    static let border = Color(red: 227 / 255, green: 233 / 255, blue: 229 / 255)
    static let borderSoft = Color(red: 231 / 255, green: 233 / 255, blue: 230 / 255)
    static let badgeBorder = Color(red: 201 / 255, green: 213 / 255, blue: 209 / 255)
    static let danger = Color(red: 0.75, green: 0.22, blue: 0.22)

    static let corner: CGFloat = 20
    static let cornerCard: CGFloat = 21
    static let cornerIcon: CGFloat = 24
}

/// Soft mint → sky → warm paper wash from the mockup hero.
struct StudydayBackground: View {
    var body: some View {
        ZStack {
            StudydayTheme.outerWash
            LinearGradient(
                colors: [
                    Color(red: 233 / 255, green: 244 / 255, blue: 239 / 255),
                    Color(red: 234 / 255, green: 241 / 255, blue: 251 / 255),
                    Color(red: 250 / 255, green: 250 / 255, blue: 248 / 255)
                ],
                startPoint: UnitPoint(x: 0.05, y: 0.0),
                endPoint: UnitPoint(x: 0.95, y: 1.0)
            )
        }
        .ignoresSafeArea()
    }
}
