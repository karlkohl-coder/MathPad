import Foundation
import Vision

/// On-device text recognition. No key, no network, no cost.
///
/// It reads prose well and needs nothing set up, but it returns text, not
/// structure: a fraction comes back as the characters that happen to be on the
/// line. Everything therefore lands as a text block, which you can retype as a
/// formula — that is the honest limit of OCR without a model behind it.
struct VisionRecognizer: WorksheetRecognizer {
    let id = "vision"
    let displayName = "Apple Vision (auf dem Gerät)"

    func unavailableReason() -> String? { nil }

    func recognize(_ image: WorksheetImage) async throws -> [Block] {
        let lines = try Self.recognizeLines(in: image.pngData)
        let blocks = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { Block(kind: .paragraph, value: ProseText.escapeHTML($0)) }
        guard !blocks.isEmpty else { throw RecognitionError.emptyResult }
        return blocks
    }

    private static func recognizeLines(in png: Data) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["de-DE", "en-US"]

        let handler = VNImageRequestHandler(data: png, options: [:])
        try handler.perform([request])

        guard let observations = request.results else { return [] }
        // Vision returns one observation per line but in no guaranteed order;
        // sort top-to-bottom, then left-to-right. Origin is bottom-left.
        return observations
            .sorted { lhs, rhs in
                let dy = rhs.boundingBox.midY - lhs.boundingBox.midY
                if abs(dy) > 0.01 { return dy < 0 }
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }
            .compactMap { $0.topCandidates(1).first?.string }
    }
}
