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
        guard let path = value("--transcribe-file"), let samples = loadSamples(path: path) else {
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
            let polisher = OpenAIPolisher(apiKey: { KeychainStore.readAPIKey() }, model: { polishModel })
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

    private static func loadSamples(path: String) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: URL(fileURLWithPath: path)),
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioRecorder.sampleRate,
                                         channels: 1, interleaved: false),
              let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                           frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: input)) != nil,
              let converter = AVAudioConverter(from: file.processingFormat, to: target) else { return nil }
        let ratio = target.sampleRate / file.processingFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed { status.pointee = .endOfStream; return nil }
            consumed = true
            status.pointee = .haveData
            return input
        }
        guard error == nil, let channel = output.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}
