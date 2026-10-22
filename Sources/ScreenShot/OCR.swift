import AppKit
import Vision

/// Text/QR recognition with Vision; the result goes to the clipboard.
enum OCR {
    @MainActor static func run(_ img: CGImage) {
        Toast.show("Recognizing…", duration: 10)
        let removeBreaks = Settings.ocrRemoveBreaks
        DispatchQueue.global(qos: .userInitiated).async {
            let result = recognize(img, removeBreaks: removeBreaks)
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

    static func recognize(_ img: CGImage, removeBreaks: Bool) -> (String, Bool)? {
        let handler = VNImageRequestHandler(cgImage: img)

        let barcodes = VNDetectBarcodesRequest()
        try? handler.perform([barcodes])
        if let payload = barcodes.results?.compactMap(\.payloadStringValue).first, !payload.isEmpty {
            return (payload, true)
        }

        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        req.automaticallyDetectsLanguage = true
        try? handler.perform([req])
        let lines = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        guard !lines.isEmpty else { return nil }
        return (lines.joined(separator: removeBreaks ? " " : "\n"), false)
    }
}
