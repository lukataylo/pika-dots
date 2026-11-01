import AVFoundation

/// Synthesised so no audio assets ship: a gliding pitch whose harmonics sweep
/// through "ee-aa-oo" vowel formants, which is what makes a tone read as "meow".
@MainActor
enum CatVoice {
    enum Sound: String, CaseIterable { case mrrp, meow, yowl }
    static let defaultsKey = "catSounds"
    static var enabled: Bool { UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true }
    private static var player: AVAudioPlayer?
    private static var cache: [Sound: Data] = [:]

    /// Plays only what the companion's skill Markdown declares, and only while sounds are on in Settings.
    static func play(_ event: SoundEvent, for agent: AgentDefinition) {
        guard let sound = SkillSounds.parse(agent.skillText)[event] else { return }
        play(sound)
    }

    static func play(_ sound: Sound) {
        guard enabled else { return }
        let data = cache[sound] ?? wav(samples(sound))
        cache[sound] = data
        player = try? AVAudioPlayer(data: data)
        player?.volume = sound == .yowl ? 0.85 : 0.55
        player?.play()
    }

    private struct Shape { let duration, start, peak, end, peakAt, trill: Double }
    private static func shape(_ sound: Sound) -> Shape {
        switch sound {
        case .mrrp: Shape(duration: 0.28, start: 420, peak: 640, end: 600, peakAt: 0.7, trill: 28)
        case .meow: Shape(duration: 0.6, start: 520, peak: 820, end: 440, peakAt: 0.35, trill: 0)
        case .yowl: Shape(duration: 0.95, start: 380, peak: 900, end: 360, peakAt: 0.45, trill: 0)
        }
    }

    nonisolated static func samples(_ sound: Sound, rate: Double = 44_100) -> [Float] {
        let s = MainActor.assumeIsolated { shape(sound) }
        let count = Int(s.duration * rate)
        var phases = [Double](repeating: 0, count: 12)
        var out = [Float](repeating: 0, count: count)
        var noise: UInt32 = 0x9E37_79B9
        for i in 0..<count {
            let t = Double(i) / rate, u = t / s.duration
            let f0 = (u < s.peakAt
                ? s.start + (s.peak - s.start) * sin(.pi / 2 * u / s.peakAt)
                : s.peak + (s.end - s.peak) * (1 - cos(.pi / 2 * (u - s.peakAt) / (1 - s.peakAt))))
                * (1 + 0.012 * sin(2 * .pi * 6 * t))
            let f1 = 450 + 550 * sin(.pi * u), f2 = 2300 - 1400 * u
            var value = 0.0
            for k in 0..<phases.count {
                let freq = f0 * Double(k + 1)
                guard freq < rate / 2 else { break }
                phases[k] += 2 * .pi * freq / rate
                let weight = exp(-pow((freq - f1) / 260, 2)) + 0.6 * exp(-pow((freq - f2) / 420, 2)) + 0.12 / Double(k + 1)
                value += weight * sin(phases[k])
            }
            noise = noise &* 1_664_525 &+ 1_013_904_223
            value += (Double(noise) / Double(UInt32.max) - 0.5) * 0.04
            let attack = min(1, t / 0.035), release = min(1, (s.duration - t) / (s.duration * 0.3))
            let trill = s.trill > 0 ? 0.65 + 0.35 * sin(2 * .pi * s.trill * t) : 1
            out[i] = Float(value * attack * max(0, release) * trill)
        }
        let peak = out.map(abs).max() ?? 1
        return peak > 0 ? out.map { $0 / peak * 0.8 } : out
    }

    nonisolated static func wav(_ samples: [Float], rate: Int = 44_100) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = samples.count * 2
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + bytes))
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(rate)); append(UInt32(rate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(UInt32(bytes))
        for sample in samples { append(Int16(max(-1, min(1, sample)) * Float(Int16.max))) }
        return data
    }
}

enum SoundEvent: String, CaseIterable { case start, drift, warning, done }

/// Reads a skill's "## Sounds" section, e.g. "- drift: meow". A cat without the section is silent.
enum SkillSounds {
    static func parse(_ markdown: String) -> [SoundEvent: CatVoice.Sound] {
        var sounds: [SoundEvent: CatVoice.Sound] = [:]
        for line in section(markdown) {
            let parts = line.trimmingCharacters(in: CharacterSet(charactersIn: "-*• \t")).lowercased().split(separator: ":", maxSplits: 1)
            guard parts.count == 2, let event = SoundEvent(rawValue: parts[0].trimmingCharacters(in: .whitespaces)),
                  let sound = CatVoice.Sound(rawValue: parts[1].trimmingCharacters(in: .whitespaces)) else { continue }
            sounds[event] = sound
        }
        return sounds
    }
    /// The skill text without its Sounds section, so sound wiring is not sent to the model.
    static func stripped(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: isSoundsHeading) else { return markdown }
        let end = lines[(start + 1)...].firstIndex { $0.hasPrefix("#") } ?? lines.endIndex
        return (lines[..<start] + lines[end...]).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func section(_ markdown: String) -> ArraySlice<String> {
        let lines = markdown.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: isSoundsHeading) else { return [] }
        let end = lines[(start + 1)...].firstIndex { $0.hasPrefix("#") } ?? lines.endIndex
        return lines[(start + 1)..<end]
    }
    private static func isSoundsHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("#") && trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).lowercased() == "sounds"
    }
}

/// Reads "## Allowed websites" from a skill: one domain per line, e.g. "- linkedin.com".
enum SkillSites {
    static func parse(_ markdown: String) -> [String] {
        let lines = markdown.components(separatedBy: .newlines)
        let isHeading = { (line: String) in line.trimmingCharacters(in: .whitespaces).hasPrefix("#")
            && line.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).lowercased() == "allowed websites" }
        guard let start = lines.firstIndex(where: isHeading) else { return [] }
        let end = lines[(start + 1)...].firstIndex { $0.hasPrefix("#") } ?? lines.endIndex
        return lines[(start + 1)..<end].compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("-") || trimmed.hasPrefix("*") else { return nil }
            var site = trimmed.dropFirst().trimmingCharacters(in: .whitespaces).lowercased()
            for prefix in ["https://", "http://", "www."] where site.hasPrefix(prefix) { site.removeFirst(prefix.count) }
            site = String(site.split(separator: "/").first ?? "")
            return site.contains(".") && !site.contains(" ") ? site : nil
        }
    }
}
