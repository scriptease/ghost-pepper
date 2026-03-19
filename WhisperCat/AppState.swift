import SwiftUI

enum AppStatus: String {
    case ready = "Ready"
    case loading = "Loading model..."
    case recording = "Recording..."
    case transcribing = "Transcribing..."
    case error = "Error"
}

@MainActor
class AppState: ObservableObject {
    @Published var status: AppStatus = .loading
    @Published var isRecording: Bool = false
    @Published var errorMessage: String?
    @AppStorage("cleanupEnabled") var cleanupEnabled: Bool = true

    let modelManager = ModelManager()
    let audioRecorder = AudioRecorder()
    let transcriber: WhisperTranscriber
    let textPaster = TextPaster()
    let soundEffects = SoundEffects()
    let hotkeyMonitor = HotkeyMonitor()
    let overlay = RecordingOverlayController()
    let textCleanupManager = TextCleanupManager()
    let textCleaner: TextCleaner

    var isReady: Bool {
        status == .ready
    }

    init() {
        self.transcriber = WhisperTranscriber(modelManager: modelManager)
        self.textCleaner = TextCleaner(cleanupManager: textCleanupManager)
    }

    func initialize() async {
        // Check microphone permission
        let hasMic = await PermissionChecker.checkMicrophone()
        if !hasMic {
            errorMessage = "Microphone access required"
            status = .error
            return
        }

        // Load WhisperKit model first (downloads on first run)
        status = .loading
        await modelManager.loadModel()

        guard modelManager.isReady else {
            errorMessage = "Failed to load whisper model: \(modelManager.error?.localizedDescription ?? "unknown error")"
            status = .error
            return
        }

        // Now try to start the hotkey monitor (needs Accessibility)
        await startHotkeyMonitor()

        // Load cleanup model in background (don't block Ready state)
        if cleanupEnabled {
            Task {
                await textCleanupManager.loadModel()
            }
        }
    }

    /// Attempts to start the hotkey monitor. Can be called again after granting Accessibility permission.
    func startHotkeyMonitor() async {
        hotkeyMonitor.onRecordingStart = { [weak self] in
            Task { @MainActor in
                self?.startRecording()
            }
        }
        hotkeyMonitor.onRecordingStop = { [weak self] in
            Task { @MainActor in
                await self?.stopRecordingAndTranscribe()
            }
        }

        if hotkeyMonitor.start() {
            status = .ready
            errorMessage = nil
        } else {
            PermissionChecker.promptAccessibility()
            errorMessage = "Accessibility access required — grant permission then click Retry"
            status = .error
        }
    }

    private func startRecording() {
        guard status == .ready else { return }

        do {
            try audioRecorder.startRecording()
            soundEffects.playStart()
            overlay.show()
            isRecording = true
            status = .recording
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
            status = .error
        }
    }

    private func stopRecordingAndTranscribe() async {
        guard status == .recording else { return }

        let buffer = audioRecorder.stopRecording()
        soundEffects.playStop()
        overlay.dismiss()
        isRecording = false
        status = .transcribing

        if let text = await transcriber.transcribe(audioBuffer: buffer) {
            let finalText: String
            if cleanupEnabled && textCleanupManager.isReady {
                finalText = await textCleaner.clean(text: text)
            } else {
                finalText = text
            }
            textPaster.paste(text: finalText)
        }

        status = .ready
    }
}
