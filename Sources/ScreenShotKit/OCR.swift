import AppKit
import Vision

/// Runs Vision requests one at a time. Simultaneous text recognitions (Library indexing, Blur Text, ⌘O) can
/// deadlock inside Vision on machines with few cores, so every request in the app goes through here.
enum VisionGate {
    private static let lock = NSLock()

    static func perform(_ requests: [VNRequest], on image: CGImage) {
        lock.lock()
        defer { lock.unlock() }
        try? VNImageRequestHandler(cgImage: image).perform(requests)
    }
}

/// Text/QR recognition with Vision; the result goes to the clipboard.
enum OCR {
    @MainActor static func run(_ img: CGImage) {
        Toast.show("Recognizing…", duration: 10)
        let removeBreaks = Settings.ocrRemoveBreaks, language = Settings.ocrLanguage
        DispatchQueue.global(qos: .userInitiated).async {
            let result = recognize(img, removeBreaks: removeBreaks, language: language)
            DispatchQueue.main.async {
                guard let (text, isQR) = result else {
                    Toast.show("No text detected")
                    return
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                let preview = text.count > 120 ? String(text.prefix(120)) + "…" : text
                Toast.show((isQR ? "QR code copied:\n" : "Text copied to the clipboard:\n") + preview, duration: 2.5)
            }
        }
    }

    /// Languages Vision can read, as (code, display name), for the "OCR main language" setting.
    static var languages: [(code: String, name: String)] {
        let codes = (try? VNRecognizeTextRequest().supportedRecognitionLanguages()) ?? ["en-US"]
        return codes.map { ($0, Locale.current.localizedString(forIdentifier: $0) ?? $0) }
    }

    /// Points Vision at the chosen language first; "auto" lets it detect the language itself.
    static func configure(_ req: VNRecognizeTextRequest, language: String) {
        if language == "auto" {
            req.automaticallyDetectsLanguage = true
        } else {
            req.automaticallyDetectsLanguage = false
            req.recognitionLanguages = [language] + (language.hasPrefix("en") ? [] : ["en-US"])
        }
    }

    static func recognize(_ img: CGImage, removeBreaks: Bool, language: String = "auto") -> (String, Bool)? {
        let barcodes = VNDetectBarcodesRequest()
        VisionGate.perform([barcodes], on: img)
        if let payload = barcodes.results?.compactMap(\.payloadStringValue).first, !payload.isEmpty {
            return (payload, true)
        }

        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        configure(req, language: language)
        VisionGate.perform([req], on: img)
        let lines = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        guard !lines.isEmpty else { return nil }
        return (lines.joined(separator: removeBreaks ? " " : "\n"), false)
    }
}
