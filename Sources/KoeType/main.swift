import Foundation

if CommandLine.arguments.contains("--transcribe-file") {
    // The main queue must keep running: model state updates are delivered on the main actor.
    Task.detached {
        exit(await TranscribeFileCommand.run(arguments: CommandLine.arguments))
    }
    dispatchMain()
}

if CommandLine.arguments.contains("--preview-indicator") {
    // Verification aid: shows the recording indicator with a synthetic voice level for a few seconds.
    IndicatorPreview.run()
}

KoeTypeApp.main()
