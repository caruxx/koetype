import AVFoundation
import Foundation
import KoeTypeCore

/// Verification aid: runs one audio file through the same transcription (and optionally
/// polishing) path the app uses, and prints the result and timings to standard output.
enum TranscribeFileCommand {
    static func run(arguments: [String]) async -> Int32 {
        func value(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        guard let path = value("--transcribe-file"), let samples = AudioFileLoader.load(path: path) else {
            FileHandle.standardError.write(Data("could not read audio file\n".utf8))
            return 2
        }
        let model = value("--model") ?? AppSettings.defaultWhisperModel
        let hints = value("--hints") ?? ""

        let transcriber = WhisperKitTranscriber()
        var started = Date()
        await transcriber.load(model: model, repo: value("--model-repo"))
        guard transcriber.isReady else {
            FileHandle.standardError.write(Data("could not load model: \(transcriber.state)\n".utf8))
            return 3
        }
        print(String(format: "load_seconds=%.2f", Date().timeIntervalSince(started)))

        if arguments.contains("--long") {
            // Long-form path used for recordings: chunked, with timestamps.
            started = Date()
            guard let segments = try? await transcriber.transcribeLong(samples: samples, hints: hints, progress: { _ in }) else {
                return 3
            }
            print(String(format: "transcribe_seconds=%.2f", Date().timeIntervalSince(started)))
            print(TranscriptFormatter.markdown(title: "記録", startedAt: Date(),
                                               durationSeconds: Double(samples.count) / AudioRecorder.sampleRate,
                                               segments: segments))
            return 0
        }

        started = Date()
        let transcript: String
        do {
            transcript = try await transcriber.transcribe(samples: samples, hints: hints)
        } catch {
            FileHandle.standardError.write(Data("transcription failed: \(error)\n".utf8))
            return 3
        }
        print(String(format: "transcribe_seconds=%.2f", Date().timeIntervalSince(started)))
        let raw = HallucinationFilter.clean(transcript)
        print("raw=\(raw)")
        print("local=\(LocalCleanup.clean(raw))")

        if arguments.contains("--polish"), !raw.isEmpty {
            let polishModel = UserDefaults.standard.string(forKey: "polishModel") ?? AppSettings.defaultPolishModel
            let polisher: Polishing = arguments.contains("--codex")
                ? CodexPolisher(executable: { AppSettings.codexPath }, model: { AppSettings.defaultCodexModel },
                                runner: ProcessRunner())
                : OpenAIPolisher(apiKey: { KeychainStore.readAPIKey() }, model: { polishModel })
            started = Date()
            do {
                let polished = try await polisher.polish(raw: raw, dictionary: [])
                print(String(format: "polish_seconds=%.2f", Date().timeIntervalSince(started)))
                print("polished=\(PolishValidator.accept(polished: polished, raw: raw) ?? raw)")
            } catch {
                print("polish_error=\(error)")
            }
        }
        return 0
    }
}
