import AVFoundation
import CoreImage
import Foundation
import ImageIO
import UIKit

struct TeethPlaygroundSample {
    let photo: UIImage
    let teethMask: UIImage?
    let sourceDescription: String
    let hasSemanticTeethMatte: Bool
}

struct TeethPlaygroundMetrics {
    let maskCoverage: Double
    let segmentedPixelCount: Int
    let averageLightness: Double
    let averageA: Double
    let averageB: Double
    let lightnessStdDev: Double
    let uniformity: Double
}

struct TeethPlaygroundAnalysis {
    let result: ScanResult
    let metrics: TeethPlaygroundMetrics
}

enum TeethPlaygroundAnalysisError: LocalizedError {
    case noImage
    case noTeethMatte
    case insufficientTeethPixels
    case imagePreparationFailed

    var errorDescription: String? {
        switch self {
        case .noImage:
            return "No photo selected."
        case .noTeethMatte:
            return "No teeth matte found. Capture with the Playground Camera on a supported device."
        case .insufficientTeethPixels:
            return "Teeth matte coverage is too low. Try a brighter smile photo."
        case .imagePreparationFailed:
            return "Unable to prepare this image for analysis."
        }
    }
}

struct TeethPlaygroundAnalyzer {
    func analyze(sample: TeethPlaygroundSample) throws -> TeethPlaygroundAnalysis {
        guard let teethMask = sample.teethMask else {
            throw TeethPlaygroundAnalysisError.noTeethMatte
        }

        let normalizedPhoto = TeethPlaygroundImagePipeline.normalizedPhoto(sample.photo)
        let alignedMask = TeethPlaygroundImagePipeline.normalizedMask(
            teethMask,
            targetSize: normalizedPhoto.size
        )

        guard
            let photoRaster = rasterizedRGBA(from: normalizedPhoto),
            let maskRaster = rasterizedRGBA(from: alignedMask),
            photoRaster.width == maskRaster.width,
            photoRaster.height == maskRaster.height
        else {
            throw TeethPlaygroundAnalysisError.imagePreparationFailed
        }

        let stats = collectLabStats(photoRaster: photoRaster, maskRaster: maskRaster)
        guard stats.segmentedPixelCount >= 700 else {
            throw TeethPlaygroundAnalysisError.insufficientTeethPixels
        }

        let nearestShade = nearestShadeForLab(l: stats.meanL, a: stats.meanA, b: stats.meanB)
        let whitenessScore = calculateWhitenessScore(
            lightness: stats.meanL,
            a: stats.meanA,
            b: stats.meanB,
            uniformity: stats.uniformity
        )
        let confidence = calculateConfidence(
            shadeDistance: nearestShade.distance,
            maskCoverage: stats.coverage,
            uniformity: stats.uniformity
        )
        let issues = detectedIssues(
            lightness: stats.meanL,
            b: stats.meanB,
            lightnessStdDev: stats.stdL,
            maskCoverage: stats.coverage
        )
        let referralNeeded = issues.contains(where: { $0.severity == "high" }) || whitenessScore < 35

        let result = ScanResult(
            whitenessScore: whitenessScore,
            shade: nearestShade.code,
            detectedIssues: issues,
            confidence: confidence,
            referralNeeded: referralNeeded,
            disclaimer: "Playground estimate generated on-device using AVSemanticSegmentationMatte. This is not a diagnosis.",
            personalTakeaway: takeaway(for: whitenessScore, issues: issues)
        )

        let metrics = TeethPlaygroundMetrics(
            maskCoverage: stats.coverage,
            segmentedPixelCount: stats.segmentedPixelCount,
            averageLightness: stats.meanL,
            averageA: stats.meanA,
            averageB: stats.meanB,
            lightnessStdDev: stats.stdL,
            uniformity: stats.uniformity
        )

        return TeethPlaygroundAnalysis(result: result, metrics: metrics)
    }
}

enum TeethPlaygroundImagePipeline {
    static func normalizedPhoto(_ image: UIImage, maxDimension: CGFloat = 1024) -> UIImage {
        normalize(image, maxDimension: maxDimension, opaque: true)
    }

    static func normalizedMask(_ image: UIImage, targetSize: CGSize) -> UIImage {
        normalize(image, targetSize: targetSize, opaque: false)
    }

    static func extractTeethMask(from imageData: Data) -> UIImage? {
        guard
            let source = CGImageSourceCreateWithData(imageData as CFData, nil),
            let auxiliaryData = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
                source,
                0,
                kCGImageAuxiliaryDataTypeSemanticSegmentationTeethMatte
            ) as? [AnyHashable: Any],
            var matte = AVSemanticSegmentationMatte(fromDictionaryRepresentation: auxiliaryData)
        else {
            return nil
        }

        if let orientation = exifOrientation(from: source) {
            matte = matte.applyingExifOrientation(orientation)
        }

        return maskImage(from: matte)
    }

    static func maskImage(from matte: AVSemanticSegmentationMatte) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: matte.mattingImage)
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private static func exifOrientation(from source: CGImageSource) -> CGImagePropertyOrientation? {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let value = properties[kCGImagePropertyOrientation] as? NSNumber
        else {
            return nil
        }
        return CGImagePropertyOrientation(rawValue: value.uint32Value)
    }

    private static func normalize(
        _ image: UIImage,
        targetSize: CGSize? = nil,
        maxDimension: CGFloat? = nil,
        opaque: Bool
    ) -> UIImage {
        let finalSize: CGSize
        if let targetSize {
            finalSize = targetSize
        } else if let maxDimension {
            let sourceSize = image.size
            let scale = min(1.0, maxDimension / max(sourceSize.width, sourceSize.height))
            finalSize = CGSize(
                width: max(1, sourceSize.width * scale),
                height: max(1, sourceSize.height * scale)
            )
        } else {
            finalSize = image.size
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = opaque
        format.scale = 1

        let renderer = UIGraphicsImageRenderer(size: finalSize, format: format)
        return renderer.image { context in
            if !opaque {
                UIColor.black.setFill()
                context.cgContext.fill(CGRect(origin: .zero, size: finalSize))
            }
            image.draw(in: CGRect(origin: .zero, size: finalSize))
        }
    }
}

private struct RGBAImage {
    let bytes: [UInt8]
    let width: Int
    let height: Int
}

private struct ShadeAnchor {
    let code: String
    let l: Double
    let a: Double
    let b: Double
}

private struct ShadeMatch {
    let code: String
    let distance: Double
}

private struct LabStats {
    let meanL: Double
    let meanA: Double
    let meanB: Double
    let stdL: Double
    let segmentedPixelCount: Int
    let coverage: Double
    let uniformity: Double
}

private func rasterizedRGBA(from image: UIImage) -> RGBAImage? {
    guard let cgImage = image.cgImage else { return nil }

    let width = cgImage.width
    let height = cgImage.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    guard let context = CGContext(
        data: &bytes,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }

    context.interpolationQuality = .high
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    return RGBAImage(bytes: bytes, width: width, height: height)
}

private func collectLabStats(photoRaster: RGBAImage, maskRaster: RGBAImage) -> LabStats {
    let matteThreshold = 0.18
    let hardPixelThreshold = 0.35
    var weightSum = 0.0
    var segmentedPixelCount = 0

    var sumL = 0.0
    var sumA = 0.0
    var sumB = 0.0
    var sumL2 = 0.0

    let totalPixels = photoRaster.width * photoRaster.height

    for pixel in 0..<totalPixels {
        let offset = pixel * 4
        let matte = Double(maskRaster.bytes[offset]) / 255.0
        if matte < matteThreshold {
            continue
        }

        if matte > hardPixelThreshold {
            segmentedPixelCount += 1
        }

        let weight = matte
        let r = Double(photoRaster.bytes[offset]) / 255.0
        let g = Double(photoRaster.bytes[offset + 1]) / 255.0
        let b = Double(photoRaster.bytes[offset + 2]) / 255.0
        let lab = rgbToLab(r: r, g: g, b: b)

        weightSum += weight
        sumL += lab.l * weight
        sumA += lab.a * weight
        sumB += lab.bValue * weight
        sumL2 += lab.l * lab.l * weight
    }

    guard weightSum > 0 else {
        return LabStats(
            meanL: 0,
            meanA: 0,
            meanB: 0,
            stdL: 0,
            segmentedPixelCount: 0,
            coverage: 0,
            uniformity: 0
        )
    }

    let meanL = sumL / weightSum
    let meanA = sumA / weightSum
    let meanB = sumB / weightSum
    let varianceL = max(0, (sumL2 / weightSum) - (meanL * meanL))
    let stdL = sqrt(varianceL)
    let coverage = Double(segmentedPixelCount) / Double(totalPixels)
    let uniformity = clamp(1.0 - (stdL / 18.0), minValue: 0, maxValue: 1)

    return LabStats(
        meanL: meanL,
        meanA: meanA,
        meanB: meanB,
        stdL: stdL,
        segmentedPixelCount: segmentedPixelCount,
        coverage: coverage,
        uniformity: uniformity
    )
}

private func calculateWhitenessScore(lightness: Double, a: Double, b: Double, uniformity: Double) -> Int {
    let lightnessFactor = clamp((lightness - 42) / 48, minValue: 0, maxValue: 1)
    let yellownessPenalty = clamp((b - 9) / 21, minValue: 0, maxValue: 1)
    let rednessPenalty = clamp((abs(a) - 1.5) / 10, minValue: 0, maxValue: 1)

    let score01 = clamp(
        (0.62 * lightnessFactor) +
            (0.23 * (1 - yellownessPenalty)) +
            (0.10 * uniformity) +
            (0.05 * (1 - rednessPenalty)),
        minValue: 0,
        maxValue: 1
    )

    return Int((score01 * 100).rounded())
}

private func calculateConfidence(shadeDistance: Double, maskCoverage: Double, uniformity: Double) -> Double {
    let shadeConfidence = clamp(1 - shadeDistance / 35, minValue: 0, maxValue: 1)
    let coverageConfidence = clamp((maskCoverage - 0.005) / 0.045, minValue: 0, maxValue: 1)
    return clamp(
        (0.5 * shadeConfidence) + (0.3 * coverageConfidence) + (0.2 * uniformity),
        minValue: 0.05,
        maxValue: 0.99
    )
}

private func nearestShadeForLab(l: Double, a: Double, b: Double) -> ShadeMatch {
    // Approximate VITA Classical shade anchors from commonly shared L*a*b* references.
    let anchors: [ShadeAnchor] = [
        ShadeAnchor(code: "B1", l: 82, a: -1, b: 8),
        ShadeAnchor(code: "A1", l: 80, a: 0, b: 12),
        ShadeAnchor(code: "B2", l: 75, a: -1, b: 14),
        ShadeAnchor(code: "A2", l: 73, a: 1, b: 16),
        ShadeAnchor(code: "C1", l: 72, a: 1, b: 13),
        ShadeAnchor(code: "D2", l: 70, a: 2, b: 18),
        ShadeAnchor(code: "A3", l: 67, a: 2, b: 20),
        ShadeAnchor(code: "B3", l: 65, a: 0, b: 22),
        ShadeAnchor(code: "D3", l: 62, a: 3, b: 24),
        ShadeAnchor(code: "C2", l: 60, a: 2, b: 23),
        ShadeAnchor(code: "C3", l: 55, a: 3, b: 28),
        ShadeAnchor(code: "D4", l: 50, a: 4, b: 30)
    ]

    let best = anchors.min { lhs, rhs in
        shadeDistance(l: l, a: a, b: b, anchor: lhs) < shadeDistance(l: l, a: a, b: b, anchor: rhs)
    } ?? anchors[0]

    return ShadeMatch(code: best.code, distance: shadeDistance(l: l, a: a, b: b, anchor: best))
}

private func shadeDistance(l: Double, a: Double, b: Double, anchor: ShadeAnchor) -> Double {
    let dl = l - anchor.l
    let da = a - anchor.a
    let db = b - anchor.b
    return sqrt((dl * dl) + (da * da) + (db * db))
}

private func detectedIssues(lightness: Double, b: Double, lightnessStdDev: Double, maskCoverage: Double) -> [DetectedIssue] {
    var issues: [DetectedIssue] = []

    if b > 23 {
        issues.append(
            DetectedIssue(
                key: "surface_staining",
                severity: "high",
                notes: "Stronger yellow tones detected; limiting coffee/tea staining can help."
            )
        )
    } else if b > 17 {
        issues.append(
            DetectedIssue(
                key: "surface_staining",
                severity: "medium",
                notes: "Mild yellow tone detected; consistent brushing and rinsing can improve shade."
            )
        )
    }

    if lightness < 54 {
        issues.append(
            DetectedIssue(
                key: "overall_brightness",
                severity: lightness < 48 ? "high" : "medium",
                notes: "Overall brightness appears low in the segmented enamel region."
            )
        )
    }

    if lightnessStdDev > 15 {
        issues.append(
            DetectedIssue(
                key: "tone_variation",
                severity: "medium",
                notes: "Uneven brightness detected across teeth, which can indicate patchy staining."
            )
        )
    }

    if maskCoverage < 0.009 {
        issues.append(
            DetectedIssue(
                key: "capture_quality",
                severity: "low",
                notes: "Limited teeth area was segmented; retake with stronger lighting and a wider smile."
            )
        )
    }

    return issues
}

private func takeaway(for score: Int, issues: [DetectedIssue]) -> String {
    if score >= 82 {
        return "Strong brightness and low stain signal. Maintain with hydration and low-pigment rinses after dark drinks."
    }

    if score >= 65 {
        if issues.contains(where: { $0.key == "surface_staining" }) {
            return "Good base shade with moderate stain tint. Focus on post-coffee rinsing and nightly flossing for steady gains."
        }
        return "You're in a healthy mid-to-bright zone. Keep routine consistency to preserve shade."
    }

    if issues.contains(where: { $0.key == "capture_quality" }) {
        return "Retake the photo with brighter frontal light and a wider smile to improve measurement reliability."
    }

    return "Lower brightness detected in this pass. Prioritize stain-control habits and consider discussing whitening options with your dentist."
}

private func rgbToLab(r: Double, g: Double, b: Double) -> (l: Double, a: Double, bValue: Double) {
    let rl = srgbToLinear(r)
    let gl = srgbToLinear(g)
    let bl = srgbToLinear(b)

    let x = (0.4124564 * rl + 0.3575761 * gl + 0.1804375 * bl) / 0.95047
    let y = 0.2126729 * rl + 0.7151522 * gl + 0.0721750 * bl
    let z = (0.0193339 * rl + 0.1191920 * gl + 0.9503041 * bl) / 1.08883

    let fx = labF(x)
    let fy = labF(y)
    let fz = labF(z)

    let l = max(0, 116 * fy - 16)
    let a = 500 * (fx - fy)
    let bValue = 200 * (fy - fz)

    return (l, a, bValue)
}

private func srgbToLinear(_ value: Double) -> Double {
    if value <= 0.04045 {
        return value / 12.92
    }
    return pow((value + 0.055) / 1.055, 2.4)
}

private func labF(_ value: Double) -> Double {
    let epsilon = 0.008856
    let kappa = 903.3
    if value > epsilon {
        return pow(value, 1.0 / 3.0)
    }
    return (kappa * value + 16) / 116
}

private func clamp(_ value: Double, minValue: Double, maxValue: Double) -> Double {
    min(max(value, minValue), maxValue)
}

