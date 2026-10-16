import Foundation
import Testing
@testable import GlasspadKit

/// Every theme, in every appearance it can show, must keep text and controls readable.
@Suite struct ThemeContrastTests {
    /// Each theme with each appearance it can actually take.
    static let cases: [(ThemeChoice, Bool)] = ThemeChoice.allCases.flatMap { theme -> [(ThemeChoice, Bool)] in
        switch theme.appearance {
        case .light: [(theme, false)]
        case .dark: [(theme, true)]
        case .followsPhone: [(theme, false), (theme, true)]
        }
    }

    private func name(_ theme: ThemeChoice, _ dark: Bool) -> String { "\(theme.title) \(dark ? "dark" : "light")" }

    private func text(_ theme: ThemeChoice) -> Double {
        theme.isHighContrast ? ContrastLevel.enhanced.rawValue : ContrastLevel.text.rawValue
    }

    @Test func inkReadsOnTheSurfaceAndOnCards() {
        for (theme, dark) in Self.cases {
            let t = theme.tokens(dark: dark)
            let onSurface = t.ink.worstContrast(on: t.surfaces)
            let onRaised = t.ink.worstContrast(on: t.raisedSurfaces)
            #expect(onSurface >= text(theme), "\(name(theme, dark)) ink on surface \(onSurface)")
            #expect(onRaised >= text(theme), "\(name(theme, dark)) ink on raised \(onRaised)")
        }
    }

    @Test func secondaryTextReadsOnTheSurfaceAndOnCards() {
        for (theme, dark) in Self.cases {
            let t = theme.tokens(dark: dark)
            let onSurface = t.inkSoft.worstContrast(on: t.surfaces)
            let onRaised = t.inkSoft.worstContrast(on: t.raisedSurfaces)
            #expect(onSurface >= text(theme), "\(name(theme, dark)) soft ink on surface \(onSurface)")
            #expect(onRaised >= text(theme), "\(name(theme, dark)) soft ink on raised \(onRaised)")
        }
    }

    @Test func accentReadsAsTextOnCardsAndAsAControlOnTheSurface() {
        for (theme, dark) in Self.cases {
            let t = theme.tokens(dark: dark)
            let onRaised = t.accent.worstContrast(on: t.raisedSurfaces)
            let onSurface = t.accent.worstContrast(on: t.surfaces)
            #expect(onRaised >= ContrastLevel.text.rawValue, "\(name(theme, dark)) accent on raised \(onRaised)")
            #expect(onSurface >= ContrastLevel.ui.rawValue, "\(name(theme, dark)) accent on surface \(onSurface)")
        }
    }

    @Test func labelsOnInkFilledButtonsRead() {
        for (theme, dark) in Self.cases {
            let t = theme.tokens(dark: dark)
            #expect(t.solid.a == 1 && t.ink.a == 1, "\(name(theme, dark)) solid and ink are opaque")
            let ratio = t.solid.contrast(with: t.ink)
            #expect(ratio >= text(theme), "\(name(theme, dark)) solid on ink \(ratio)")
        }
    }

    @Test func statusColoursReadAndKeepTheirMeaning() {
        for (theme, dark) in Self.cases {
            let t = theme.tokens(dark: dark)
            for (label, c) in [("good", t.good), ("caution", t.caution), ("bad", t.bad)] {
                let ratio = c.worstContrast(on: t.allSurfaces)
                #expect(ratio >= ContrastLevel.ui.rawValue, "\(name(theme, dark)) \(label) \(ratio)")
            }
            // Still green, orange and red: never pushed all the way to the ink.
            #expect(t.good.g > t.good.r && t.bad.r > t.bad.g && t.caution.r > t.caution.b, "\(name(theme, dark)) status hues")
        }
    }

    @Test func everySystemColourCanBeMadeReadableAsAModeAccent() {
        for (theme, dark) in Self.cases {
            let t = theme.tokens(dark: dark)
            for hue in SystemHue.allCases {
                let c = t.readable(hue.value(dark: dark))
                #expect(c.worstContrast(on: t.allSurfaces) >= ContrastLevel.ui.rawValue, "\(name(theme, dark)) \(hue)")
            }
        }
    }

    @Test func colourThatAlreadyReadsIsLeftAlone() {
        let t = ThemeChoice.paper.tokens(dark: false)
        let blue = SystemHue.blue.value(dark: false)
        #expect(t.readable(blue) == blue)
    }

    @Test func cardsStandApartFromTheSurfaceAndDotsShow() {
        for (theme, dark) in Self.cases {
            let t = theme.tokens(dark: dark)
            #expect(t.isDark == dark || theme.appearance != .followsPhone)
            #expect(t.line.a > 0 && t.dot.a > 0 && t.inkSoft.a < 1, "\(name(theme, dark)) tokens")
            #expect(t.dot.over(t.background).contrast(with: t.background) > 1.1, "\(name(theme, dark)) dot shows")
            if !theme.isGlass {
                #expect(t.raised != t.background, "\(name(theme, dark)) raised differs from surface")
            }
            #expect((t.backdrop != nil) == theme.isGlass, "\(name(theme, dark)) backdrop")
        }
    }

    @Test func darkThemesHaveLightInkAndLightThemesDarkInk() {
        for (theme, dark) in Self.cases {
            let t = theme.tokens(dark: dark)
            #expect(t.isDark == dark, "\(name(theme, dark)) appearance")
            #expect(dark ? t.ink.luminance > 0.6 : t.ink.luminance < 0.1, "\(name(theme, dark)) ink")
        }
    }

    @Test func savedChoicesFromOlderBuildsStillLoad() {
        for raw in ["paper", "graphite", "system", "mono", "sand", "midnight", "glass", "glassDark"] {
            #expect(ThemeChoice(saved: raw).rawValue == raw)
        }
        #expect(ThemeChoice(saved: "sunset") == .system)
        #expect(ThemeChoice(saved: nil) == .system)
        #expect(ThemeChoice(saved: "") == .system)
    }

    @Test func everyThemeHasAGroupAndAUniqueName() {
        let groups = ThemeChoice.Group.allCases.flatMap(\.themes)
        #expect(groups.count == ThemeChoice.allCases.count)
        #expect(Set(ThemeChoice.allCases.map(\.title)).count == ThemeChoice.allCases.count)
    }

    @Test func backdropsMirrorAcrossTheDiagonal() {
        for theme in ThemeChoice.allCases where theme.isGlass {
            for dark in [false, true] {
                guard let b = theme.tokens(dark: dark).backdrop else { continue }
                for p in b.pools {
                    #expect(b.pools.contains { $0.x == p.y && $0.y == p.x && $0.color == p.color }, "\(theme.title)")
                }
            }
        }
    }

    @Test func contrastMathMatchesWCAG() {
        #expect(abs(RGBA.black.contrast(with: .white) - 21) < 0.001)
        #expect(abs(RGBA(hex: 0x767676).contrast(with: .white) - 4.54) < 0.01)
        let half = RGBA(white: 0, alpha: 0.5).over(.white)
        #expect(abs(half.r - 0.5) < 0.0001 && half.a == 1)
    }
}

/// The Photo theme must read on any photo.
@Suite struct PhotoToneTests {
    /// A small fixed random source, so the test is the same every run.
    struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    @Test func everyPhotoGetsReadableColours() {
        var rng = Seeded(state: 7)
        for _ in 0..<120 {
            // A photo is mostly one mood with a few brighter or darker patches.
            let base = RGBA(r: .random(in: 0...1, using: &rng), g: .random(in: 0...1, using: &rng), b: .random(in: 0...1, using: &rng))
            let samples = (0..<64).map { _ in
                base.mixed(with: RGBA(r: .random(in: 0...1, using: &rng), g: .random(in: 0...1, using: &rng),
                                      b: .random(in: 0...1, using: &rng)), amount: .random(in: 0...0.8, using: &rng))
            }
            let tone = PhotoTone.fit(samples: samples)
            #expect(tone.tokens.meetsContrast(), "\(base) veil \(tone.veil)")
            #expect(tone.tokens.good.worstContrast(on: tone.tokens.allSurfaces) >= ContrastLevel.ui.rawValue)
        }
    }

    @Test func plainPhotosNeedNoVeil() {
        let white = PhotoTone.fit(samples: [RGBA(white: 0.97)])
        #expect(!white.isDark && white.veil == 0)
        let black = PhotoTone.fit(samples: [RGBA(hex: 0x080A10)])
        #expect(black.isDark && black.veil == 0)
    }

    @Test func busyPhotoIsCalmedByAVeil() {
        let tone = PhotoTone.fit(samples: [.white, .black, RGBA(hex: 0xFF3B30), RGBA(hex: 0x007AFF)])
        #expect(tone.veil > 0)
        #expect(tone.tokens.meetsContrast())
    }

    @Test func catalogThemesPassTheSameCheck() {
        for (theme, dark) in ThemeContrastTests.cases {
            #expect(theme.tokens(dark: dark).meetsContrast(text: theme.isHighContrast ? 7 : 4.5), "\(theme.title)")
        }
    }
}
