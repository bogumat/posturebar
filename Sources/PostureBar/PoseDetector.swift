import CoreVideo
import Foundation
import Vision

final class PoseDetector {
    private let request = VNDetectFaceRectanglesRequest()
    private let sequenceHandler = VNSequenceRequestHandler()
    private let minimumConfidence: VNConfidence = 0.30

    func detect(in pixelBuffer: CVPixelBuffer) -> PostureFeatures? {
        do {
            try sequenceHandler.perform([request], on: pixelBuffer, orientation: .up)
        } catch {
            return nil
        }

        guard let observation = request.results?
            .filter({ $0.confidence >= minimumConfidence })
            .max(by: { area(of: $0.boundingBox) < area(of: $1.boundingBox) }) else {
            return nil
        }

        let face = observation.boundingBox
        guard face.width > 0.04, face.height > 0.04 else { return nil }

        return PostureFeatures(
            headY: Double(face.midY),
            headSize: Double(sqrt(face.width * face.height))
        )
    }

    private func area(of rectangle: CGRect) -> CGFloat {
        rectangle.width * rectangle.height
    }
}
