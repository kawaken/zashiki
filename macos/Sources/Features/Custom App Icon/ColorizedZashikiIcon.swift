import Cocoa

struct ColorizedZashikiIcon {
    /// The colors that make up the gradient of the screen.
    let screenColors: [NSColor]

    /// The frame type to use
    let frame: Zashiki.MacOSIconFrame

    /// Make a custom colorized Zashiki icon.
    func makeImage(in bundle: Bundle) -> NSImage? {
        // All of our layers (not in order)
        guard let screen = bundle.image(forResource: "CustomIconScreen") else { return nil }
        guard let screenMask = bundle.image(forResource: "CustomIconScreenMask") else { return nil }
        guard let crt = bundle.image(forResource: "CustomIconCRT") else { return nil }
        guard let gloss = bundle.image(forResource: "CustomIconGloss") else { return nil }

        let baseName = switch frame {
        case .aluminum: "CustomIconBaseAluminum"
        case .beige: "CustomIconBaseBeige"
        case .chrome: "CustomIconBaseChrome"
        case .plastic: "CustomIconBasePlastic"
        }
        guard let base = bundle.image(forResource: baseName) else { return nil }

        // Apply our color in various ways to our layers.
        // NOTE: These functions are not built-in, they're implemented as an extension
        // to NSImage in NSImage+Extension.swift.
        guard let screenGradient = screenMask.gradient(colors: screenColors) else { return nil }
        // Combine our layers using the proper blending modes
        return.combine(images: [
            base,
            screen,
            screenGradient,
            crt,
            gloss,
        ], blendingModes: [
            .normal,
            .normal,
            .color,
            .overlay,
            .normal,
        ])
    }
}

// MARK: Codable

extension ColorizedZashikiIcon: Codable {
    private enum CodingKeys: String, CodingKey {
        case version
        case screenColors
        // Kept for decoding compatibility with icons saved before the logo
        // layer was removed. New values are no longer encoded.
        case ghostColor
        case frame

        static let currentVersion: Int = 1
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // If no version exists then this is the legacy v0 format.
        let version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 0
        guard version == 0 || version == CodingKeys.currentVersion else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unsupported ColorizedZashikiIcon version: \(version)"
                )
            )
        }

        let screenColorHexes = try container.decode([String].self, forKey: .screenColors)
        let screenColors = screenColorHexes.compactMap(NSColor.init(hex:))
        _ = try container.decodeIfPresent(String.self, forKey: .ghostColor)
        let frame = try container.decode(Zashiki.MacOSIconFrame.self, forKey: .frame)
        self.init(screenColors: screenColors, frame: frame)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(CodingKeys.currentVersion, forKey: .version)
        try container.encode(screenColors.compactMap(\.hexString), forKey: .screenColors)
        try container.encode(frame, forKey: .frame)
    }

}

// MARK: Equatable

extension ColorizedZashikiIcon: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.frame == rhs.frame &&
            lhs.screenColors.compactMap(\.hexString) == rhs.screenColors.compactMap(\.hexString)
    }
}
