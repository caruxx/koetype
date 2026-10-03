import Foundation

public enum AudioMixer {
    /// Adds two mono streams sample by sample, clipping to the valid range.
    public static func mix(_ first: [Float], _ second: [Float]) -> [Float] {
        let (longer, shorter) = first.count >= second.count ? (first, second) : (second, first)
        var mixed = longer
        for index in shorter.indices {
            mixed[index] = max(-1, min(1, longer[index] + shorter[index]))
        }
        return mixed
    }
}

public enum AudioChunker {
    /// Splits long audio into pieces of at most `targetSeconds`, cutting at the quietest
    /// half second within the last `searchSeconds` of each piece so words are not cut in two.
    public static func ranges(for samples: [Float], sampleRate: Double,
                              targetSeconds: Double, searchSeconds: Double) -> [Range<Int>] {
        let target = Int(targetSeconds * sampleRate)
        let search = Int(searchSeconds * sampleRate)
        let window = max(1, Int(0.5 * sampleRate))
        var ranges: [Range<Int>] = []
        var start = 0
        while samples.count - start > target {
            let limit = start + target
            let from = max(start + window, limit - search)
            var bestCentre = limit
            var bestEnergy = Float.greatestFiniteMagnitude
            var energy: Float = 0
            // Sliding sum of squares over one window.
            for index in from..<(from + window) { energy += samples[index] * samples[index] }
            var position = from
            while position + window <= limit {
                if energy < bestEnergy {
                    bestEnergy = energy
                    bestCentre = position + window / 2
                }
                let leaving = samples[position], entering = position + window < samples.count ? samples[position + window] : 0
                energy += entering * entering - leaving * leaving
                position += 1
            }
            ranges.append(start..<bestCentre)
            start = bestCentre
        }
        if start < samples.count || ranges.isEmpty { ranges.append(start..<samples.count) }
        return ranges
    }
}

public enum TranscriptFormatter {
    public static func markdown(title: String, startedAt: Date, durationSeconds: Double,
                                segments: [SpeechSegment], timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        var lines = ["# \(title) \(formatter.string(from: startedAt))", "", "- 長さ: \(clock(durationSeconds))", ""]
        let spoken = segments.compactMap { segment -> String? in
            let text = HallucinationFilter.clean(segment.text)
            return text.isEmpty ? nil : "[\(clock(segment.start))] \(text)"
        }
        lines.append(contentsOf: spoken.isEmpty ? ["（聞き取れた音声がありませんでした）"] : spoken)
        return lines.joined(separator: "\n") + "\n"
    }

    public static func fileName(title: String, startedAt: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        let safe = String(title.map { "/:\\".contains($0) ? "-" : $0 })
        return "\(formatter.string(from: startedAt))_\(safe).md"
    }

    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    }
}
