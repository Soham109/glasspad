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

    @Test func newerThemesLoadByName() {
        for raw in ["grain", "grainDark", "risograph", "film", "monoBlue", "monoSlate", "customTint"] {
            #expect(ThemeChoice(saved: raw).rawValue == raw)
        }
    }

    // MARK: Grain

    @Test func grainThemesCheckTheGrainAtItsDarkestAndLightest() {
        for theme in ThemeChoice.Group.grain.themes {
            let t = theme.tokens(dark: theme.appearance == .dark)
            let grain = try! #require(t.grain, "\(theme.title)")
            #expect(t.surfaces.count == 3 && t.surfaces.contains(t.background))
            let lightest = t.surfaces.map(\.luminance).max()!, darkest = t.surfaces.map(\.luminance).min()!
            #expect(lightest > t.background.luminance && darkest < t.background.luminance, "\(theme.title) grain shows")
            // Fine, not loud: never more than a tenth of full scale either way.
            #expect(grain.amount > 0.02 && grain.amount <= 0.1, "\(theme.title)")
        }
        #expect(ThemeChoice.paper.tokens(dark: false).grain == nil)
    }

    @Test func grainIsTheSameEveryTimeAndRepeatsWithoutASeam() {
        for scale in [1.0, 1.5, 2.0] {
            let a = ThemeGrain.noise(side: 64, pixelsPerGrain: scale), b = ThemeGrain.noise(side: 64, pixelsPerGrain: scale)
            #expect(a == b)
            #expect(a.count == 64 * 64)
            #expect(a.min()! >= 0 && a.max()! <= 1)
            let mean = a.reduce(0, +) / Double(a.count)
            #expect(abs(mean - 0.5) < 0.01)
            // Across the wrap (last column to first) neighbours differ no more than inside the tile.
            func step(_ x0: Int, _ x1: Int) -> Double {
                (0..<64).map { abs(a[$0 * 64 + x0] - a[$0 * 64 + x1]) }.reduce(0, +) / 64
            }
            let inside = (0..<63).map { step($0, $0 + 1) }.reduce(0, +) / 63
            #expect(step(63, 0) < inside * 1.6, "seam at \(scale)")
        }
        // Grain spanning more pixels is smoother from one pixel to the next.
        func roughness(_ n: [Double]) -> Double { (0..<(64 * 63)).map { abs(n[$0] - n[$0 + 1]) }.reduce(0, +) }
        #expect(roughness(ThemeGrain.noise(side: 64, pixelsPerGrain: 2)) < roughness(ThemeGrain.noise(side: 64, pixelsPerGrain: 1)))
    }

    // MARK: Tinted

    /// Hue of a colour with some colour in it, 0...1.
    private func hue(_ c: RGBA) -> Double { ThemeTint(c).hue }

    private func sameHue(_ a: Double, _ b: Double) -> Bool {
        let d = abs(a - b)
        return min(d, 1 - d) < 0.02
    }

    @Test func tintedThemesUseOneHueForEverything() {
        for theme in ThemeChoice.Group.tinted.themes {
            let tint = try! #require(theme.tint)
            for dark in [false, true] {
                let t = theme.tokens(dark: dark)
                #expect(t.tint == tint)
                for (label, c) in [("surface", t.background), ("raised", t.raised), ("ink", t.ink), ("accent", t.accent)]
                    where ThemeTint(c).saturation > 0.08 {
                    #expect(sameHue(hue(c), tint.hue), "\(name(theme, dark)) \(label)")
                }
                // Mode colours move onto the hue and still read.
                for system in SystemHue.allCases {
                    let c = t.readable(tint.mapped(system.value(dark: dark)))
                    #expect(c.worstContrast(on: t.allSurfaces) >= ContrastLevel.ui.rawValue, "\(name(theme, dark)) \(system)")
                    if tint.saturation > 0.3 { #expect(sameHue(hue(c), tint.hue), "\(name(theme, dark)) \(system) hue") }
                }
            }
        }
        #expect(ThemeChoice.mono.tint == nil && ThemeChoice.paper.tint == nil)
    }

    /// Custom Tint takes any colour the person picks, so every hue and strength must work.
    @Test func anyCustomTintReads() {
        for h in stride(from: 0.0, to: 1.0, by: 1.0 / 36) {
            for s in [0.0, 0.25, 0.5, 0.75, 1.0] {
                let tint = ThemeTint(hue: h, saturation: s)
                for dark in [false, true] {
                    let t = tint.tokens(dark: dark)
                    #expect(t.meetsContrast(), "hue \(h) saturation \(s) dark \(dark)")
                    #expect(dark ? t.ink.luminance > 0.6 : t.ink.luminance < 0.1)
                    #expect(t.dot.over(t.background).contrast(with: t.background) > 1.1)
                    #expect(t.raised.contrast(with: t.background) > 1.08, "cards stand apart at hue \(h)")
                    for system in SystemHue.allCases {
                        let c = t.readable(tint.mapped(system.value(dark: dark)))
                        #expect(c.worstContrast(on: t.allSurfaces) >= ContrastLevel.ui.rawValue)
                    }
                }
            }
        }
    }

    @Test func customTintRemembersTheColourItWasGiven() {
        let saved = ThemeTint.custom
        defer { ThemeTint.custom = saved }
        let picked = ThemeTint(RGBA(hex: 0xC2185B))
        ThemeTint.custom = picked
        #expect(ThemeChoice.customTint.tint == picked)
        #expect(ThemeTint(RGBA(hex: picked.hex)).hue.distance(to: picked.hue).magnitude < 0.01)
        #expect(ThemeTint(.white).saturation == 0)
    }

    /// Tinted icons keep their detail: the ramp from an icon's darkest to its lightest parts
    /// always gets brighter, and its ends are far enough apart for a symbol on an icon to read.
    @Test func tintedIconsKeepTheirDetail() {
        var tints = ThemeChoice.Group.tinted.themes.compactMap(\.tint)
        tints += stride(from: 0.0, to: 1.0, by: 1.0 / 24).map { ThemeTint(hue: $0, saturation: 1) }
        for tint in tints {
            for dark in [false, true] {
                let ramp = tint.iconRamp(dark: dark)
                #expect(ramp.count == ThemeTint.rampSteps)
                for i in 1..<ramp.count { #expect(ramp[i].luminance > ramp[i - 1].luminance) }
                let span = ramp.first!.contrast(with: ramp.last!)
                #expect(span >= ContrastLevel.text.rawValue, "\(tint) dark \(dark) span \(span)")
                if tint.saturation > 0.3 {
                    for c in ramp[32..<224] { #expect(sameHue(hue(c), tint.hue)) }
                }
                // A dark theme's icons never glare: their brightest is well short of white.
                if dark { #expect(ramp.last!.luminance < 0.5) }
            }
        }
        #expect(ThemeTint.grayRamp.first == .black && ThemeTint.grayRamp.last == .white)
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

    /// Filled buttons in a colour (Split, Keep, Open in Dock, Clipboard's Send) put their label in
    /// white or near black, whichever reads: white text on bright teal or yellow did not.
    @Test func labelsOnColouredButtonsRead() {
        for (theme, dark) in ThemeContrastTests.cases {
            let where_ = "\(theme.title) \(dark ? "dark" : "light")"
            let t = theme.tokens(dark: dark)
            let fills = SystemHue.allCases.map { t.readable($0.value(dark: dark)) } + [t.accent, t.good, t.caution, t.bad]
            for fill in fills {
                let label = fill.labelOnFill
                let chosen = label.contrast(with: fill)
                let other = (label == .white ? RGBA.nearBlack : .white).contrast(with: fill)
                // The better of the two whenever that one reaches body text level, and never
                // below the 4.3 the crossover point gives.
                #expect(chosen >= ContrastLevel.text.rawValue || other < ContrastLevel.text.rawValue,
                        "\(where_) label on \(fill): \(chosen) where \(other) was possible")
                #expect(chosen >= 4.3, "\(where_) label on \(fill): \(chosen)")
            }
        }
        // The colours from the report get dark labels, a deep one keeps white.
        for hue in [SystemHue.teal, .mint, .yellow, .cyan] {
            #expect(hue.value(dark: false).labelOnFill == .nearBlack && hue.value(dark: true).labelOnFill == .nearBlack, "\(hue)")
        }
        #expect(SystemHue.indigo.value(dark: false).labelOnFill == .white)
    }

    @Test func catalogThemesPassTheSameCheck() {
        for (theme, dark) in ThemeContrastTests.cases {
            #expect(theme.tokens(dark: dark).meetsContrast(text: theme.isHighContrast ? 7 : 4.5), "\(theme.title)")
        }
    }
}
