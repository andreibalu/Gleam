import AVFoundation
import CoreImage
import Foundation
import ImageIO
import UIKit

enum TeethPlaygroundSampleSource: String {
    case camera
    case library
}

struct TeethPlaygroundCaptureContext {
    let source: TeethPlaygroundSampleSource
    let lowLightDetected: Bool
    let lightingAssistEnabled: Bool
    let lightingAssistUsed: Bool
    let screenFlashFired: Bool
}

struct TeethPlaygroundSample {
    let photo: UIImage
    let teethMask: UIImage?
    let sourceDescription: String
    let hasSemanticTeethMatte: Bool
    let captureContext: TeethPlaygroundCaptureContext
}

struct TeethPlaygroundMetrics {
    let maskCoverage: Double
    let weightedCoverage: Double
    let segmentedPixelCount: Int
    let corePixelCount: Int
    let averageLightness: Double
    let averageA: Double
    let averageB: Double
    let lightnessStdDev: Double
    let uniformity: Double
    let shadeDistance: Double
    let teethSignalQuality: Double
    let lightingQuality: Double
    let confidenceBase: Double
    let limitingFactor: String
    let lowLightDetected: Bool
    let lightingAssistEnabled: Bool
    let lightingAssistUsed: Bool
    let screenFlashFired: Bool
    let qualityFlags: [String]
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
        guard stats.segmentedPixelCount >= 550, stats.corePixelCount >= 260, stats.weightedCoverage >= 0.002 else {
            throw TeethPlaygroundAnalysisError.insufficientTeethPixels
        }

        let nearestShade = nearestShadeForLab(l: stats.meanL, a: stats.meanA, b: stats.meanB)
        let whitenessScore = calculateWhitenessScore(
            lightness: stats.meanL,
            a: stats.meanA,
            b: stats.meanB,
            uniformity: stats.uniformity
        )
        var confidence = calculateConfidence(
            stats: stats,
            shadeDistance: nearestShade.distance,
            lowLightDetected: sample.captureContext.lowLightDetected,
            lightingAssistUsed: sample.captureContext.lightingAssistUsed
        )
        let qualityFlags = captureQualityFlags(
            stats: stats,
            confidence: confidence.value,
            lowLightDetected: sample.captureContext.lowLightDetected,
            limitingFactor: confidence.limitingFactor
        )
        if qualityFlags.contains("low_coverage") || qualityFlags.contains("high_variance") {
            confidence = ConfidenceBreakdown(
                base: confidence.base,
                value: min(confidence.value, 0.58),
                teethSignal: confidence.teethSignal,
                lightingQuality: confidence.lightingQuality,
                limitingFactor: confidence.limitingFactor
            )
        }
        let issues = detectedIssues(
            lightness: stats.meanL,
            b: stats.meanB,
            lightnessStdDev: stats.stdL,
            maskCoverage: stats.coverage
        )
        let referralNeeded = issues.contains(where: { $0.severity == "high" }) || whitenessScore < 35
        let disclaimer = buildDisclaimer(
            confidence: confidence.value,
            flags: qualityFlags,
            limitingFactor: confidence.limitingFactor
        )
        let takeaway = buildTakeaway(
            score: whitenessScore,
            issues: issues,
            confidence: confidence.value,
            limitingFactor: confidence.limitingFactor
        )

        let result = ScanResult(
            whitenessScore: whitenessScore,
            shade: nearestShade.code,
            detectedIssues: issues,
            confidence: confidence.value,
            referralNeeded: referralNeeded,
            disclaimer: disclaimer,
            personalTakeaway: takeaway
        )

        let metrics = TeethPlaygroundMetrics(
            maskCoverage: stats.coverage,
            weightedCoverage: stats.weightedCoverage,
            segmentedPixelCount: stats.segmentedPixelCount,
            corePixelCount: stats.corePixelCount,
            averageLightness: stats.meanL,
            averageA: stats.meanA,
            averageB: stats.meanB,
            lightnessStdDev: stats.stdL,
            uniformity: stats.uniformity,
            shadeDistance: nearestShade.distance,
            teethSignalQuality: confidence.teethSignal,
            lightingQuality: confidence.lightingQuality,
            confidenceBase: confidence.base,
            limitingFactor: confidence.limitingFactor,
            lowLightDetected: sample.captureContext.lowLightDetected,
            lightingAssistEnabled: sample.captureContext.lightingAssistEnabled,
            lightingAssistUsed: sample.captureContext.lightingAssistUsed,
            screenFlashFired: sample.captureContext.screenFlashFired,
            qualityFlags: qualityFlags
        )

        logAnalysisSummary(sample: sample, result: result, metrics: metrics)
        return TeethPlaygroundAnalysis(result: result, metrics: metrics)
    }

    private func logAnalysisSummary(
        sample: TeethPlaygroundSample,
        result: ScanResult,
        metrics: TeethPlaygroundMetrics
    ) {
        let flags = metrics.qualityFlags.isEmpty ? "none" : metrics.qualityFlags.joined(separator: "|")
        print(
            "[TeethPlaygroundAnalysis] source=\(sample.captureContext.source.rawValue) confidence=\(Int((result.confidence * 100).rounded())) whiteness=\(result.whitenessScore) shade=\(result.shade) ts=\(Int((metrics.teethSignalQuality * 100).rounded())) lq=\(Int((metrics.lightingQuality * 100).rounded())) lowLight=\(yesNo(metrics.lowLightDetected)) assistEnabled=\(yesNo(metrics.lightingAssistEnabled)) assistFired=\(yesNo(metrics.lightingAssistUsed)) coverage=\(fmt(metrics.maskCoverage)) weightedCoverage=\(fmt(metrics.weightedCoverage)) segmented=\(metrics.segmentedPixelCount) core=\(metrics.corePixelCount) L=\(fmt(metrics.averageLightness)) stdL=\(fmt(metrics.lightnessStdDev)) shadeDistance=\(fmt(metrics.shadeDistance)) limiting=\(metrics.limitingFactor) flags=\(flags)"
        )
    }

    private func yesNo(_ value: Bool) -> String {
        value ? "yes" : "no"
    }

    private func fmt(_ value: Double) -> String {
        String(format: "%.4f", value)
    }
}

enum TeethPlaygroundImagePipeline {
    private static let verbosePipelineLogsEnabled = false

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
            var matte = try? AVSemanticSegmentationMatte(
                fromImageSourceAuxiliaryDataType: kCGImageAuxiliaryDataTypeSemanticSegmentationTeethMatte,
                dictionaryRepresentation: auxiliaryData
            )
        else {
            return nil
        }

        if let orientation = exifOrientation(from: source) {
            matte = matte.applyingExifOrientation(orientation)
        }

        return maskImage(from: matte)
    }

    static func maskImage(from matte: AVSemanticSegmentationMatte) -> UIImage? {
        let pixelBuffer = matte.mattingImage
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        log("maskImage input buffer: \(width)x\(height), format: \(pixelFormat)")

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            log("maskImage failed: CIContext.createCGImage returned nil for extent \(ciImage.extent)")
            return nil
        }
        log("maskImage conversion success: cgImage \(cgImage.width)x\(cgImage.height)")
        return UIImage(cgImage: cgImage)
    }

    private static func log(_ message: String) {
        guard verbosePipelineLogsEnabled else { return }
        print("[TeethPlaygroundPipeline] \(message)")
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
    let corePixelCount: Int
    let coverage: Double
    let weightedCoverage: Double
    let uniformity: Double
}

private struct ConfidenceBreakdown {
    let base: Double
    let value: Double
    let teethSignal: Double
    let lightingQuality: Double
    let limitingFactor: String
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
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    ) else {
        return nil
    }

    context.interpolationQuality = .high
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    return RGBAImage(bytes: bytes, width: width, height: height)
}

private func collectLabStats(photoRaster: RGBAImage, maskRaster: RGBAImage) -> LabStats {
    let matteThreshold = 0.12
    let hardPixelThreshold = 0.35
    let corePixelThreshold = 0.45
    var coverageWeightSum = 0.0
    var segmentedPixelCount = 0
    var coreSamples: [(l: Double, a: Double, b: Double, weight: Double)] = []

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

        coverageWeightSum += matte

        if matte < corePixelThreshold {
            continue
        }

        let r = Double(photoRaster.bytes[offset]) / 255.0
        let g = Double(photoRaster.bytes[offset + 1]) / 255.0
        let b = Double(photoRaster.bytes[offset + 2]) / 255.0
        let lab = rgbToLab(r: r, g: g, b: b)
        coreSamples.append((l: lab.l, a: lab.a, b: lab.bValue, weight: matte))
    }

    let weightedCoverage = coverageWeightSum / Double(totalPixels)

    guard !coreSamples.isEmpty else {
        return LabStats(
            meanL: 0,
            meanA: 0,
            meanB: 0,
            stdL: 0,
            segmentedPixelCount: 0,
            corePixelCount: 0,
            coverage: 0,
            weightedCoverage: 0,
            uniformity: 0
        )
    }

    let trimmedSamples = trimmedLabSamples(coreSamples)
    let (meanL, meanA, meanB, varianceL) = weightedLabMoments(trimmedSamples)
    let stdL = sqrt(varianceL)
    let coverage = Double(segmentedPixelCount) / Double(totalPixels)
    let uniformity = clamp(1.0 - (stdL / 22.0), minValue: 0, maxValue: 1)

    return LabStats(
        meanL: meanL,
        meanA: meanA,
        meanB: meanB,
        stdL: stdL,
        segmentedPixelCount: segmentedPixelCount,
        corePixelCount: trimmedSamples.count,
        coverage: coverage,
        weightedCoverage: weightedCoverage,
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

private func calculateConfidence(
    stats: LabStats,
    shadeDistance: Double,
    lowLightDetected: Bool,
    lightingAssistUsed: Bool
) -> ConfidenceBreakdown {
    let teethSignal = teethSignalQuality(stats: stats, shadeDistance: shadeDistance)
    let lightingQuality = lightingQualityScore(
        stats: stats,
        lowLightDetected: lowLightDetected,
        lightingAssistUsed: lightingAssistUsed
    )
    let base = (0.60 * teethSignal) + (0.40 * lightingQuality)
    let confidence = clamp(base, minValue: 0.15, maxValue: 0.95)

    return ConfidenceBreakdown(
        base: base,
        value: confidence,
        teethSignal: teethSignal,
        lightingQuality: lightingQuality,
        limitingFactor: limitingFactor(teethSignal: teethSignal, lightingQuality: lightingQuality)
    )
}

private func teethSignalQuality(stats: LabStats, shadeDistance: Double) -> Double {
    let lScore = clamp((stats.meanL - 35.0) / 40.0, minValue: 0, maxValue: 1)
    let aScore = 1 - clamp(abs(stats.meanA - 1.0) / 14.0, minValue: 0, maxValue: 1)
    let bScore = 1 - clamp(abs(stats.meanB - 18.0) / 16.0, minValue: 0, maxValue: 1)
    let areaScore = clamp((stats.weightedCoverage - 0.0025) / 0.0085, minValue: 0, maxValue: 1)
    let shadeSupport = clamp(1 - shadeDistance / 28.0, minValue: 0, maxValue: 1)

    return clamp(
        (0.32 * lScore)
            + (0.20 * aScore)
            + (0.18 * bScore)
            + (0.15 * areaScore)
            + (0.15 * shadeSupport),
        minValue: 0,
        maxValue: 1
    )
}

private func lightingQualityScore(stats: LabStats, lowLightDetected: Bool, lightingAssistUsed: Bool) -> Double {
    let brightnessScore = clamp((stats.meanL - 32.0) / 38.0, minValue: 0, maxValue: 1)
    let varianceScore = clamp(1 - (stats.stdL / 18.0), minValue: 0, maxValue: 1)
    let lowLightScore = lowLightDetected ? (lightingAssistUsed ? 0.48 : 0.32) : 0.88
    let assistBonus = lightingAssistUsed ? 0.05 : 0.0

    return clamp(
        (0.55 * lowLightScore)
            + (0.30 * brightnessScore)
            + (0.15 * varianceScore)
            + assistBonus,
        minValue: 0,
        maxValue: 1
    )
}

private func limitingFactor(teethSignal: Double, lightingQuality: Double) -> String {
    if teethSignal < lightingQuality, teethSignal < 0.55 {
        return "teeth_signal"
    }
    if lightingQuality < teethSignal, lightingQuality < 0.55 {
        return "lighting"
    }
    return "balanced"
}

private func trimmedLabSamples(
    _ samples: [(l: Double, a: Double, b: Double, weight: Double)],
    trimFraction: Double = 0.08
) -> [(l: Double, a: Double, b: Double, weight: Double)] {
    guard samples.count >= 32 else { return samples }
    let sorted = samples.sorted { $0.l < $1.l }
    let trimCount = Int(Double(sorted.count) * trimFraction)
    guard trimCount > 0, (trimCount * 2) < sorted.count else { return samples }
    return Array(sorted[trimCount..<(sorted.count - trimCount)])
}

private func weightedLabMoments(
    _ samples: [(l: Double, a: Double, b: Double, weight: Double)]
) -> (meanL: Double, meanA: Double, meanB: Double, varianceL: Double) {
    guard !samples.isEmpty else { return (0, 0, 0, 0) }

    var weightSum = 0.0
    var sumL = 0.0
    var sumA = 0.0
    var sumB = 0.0
    var sumL2 = 0.0

    for sample in samples {
        weightSum += sample.weight
        sumL += sample.l * sample.weight
        sumA += sample.a * sample.weight
        sumB += sample.b * sample.weight
        sumL2 += sample.l * sample.l * sample.weight
    }

    guard weightSum > 0 else { return (0, 0, 0, 0) }
    let meanL = sumL / weightSum
    let meanA = sumA / weightSum
    let meanB = sumB / weightSum
    let varianceL = max(0, (sumL2 / weightSum) - (meanL * meanL))
    return (meanL, meanA, meanB, varianceL)
}

private func captureQualityFlags(
    stats: LabStats,
    confidence: Double,
    lowLightDetected: Bool,
    limitingFactor: String
) -> [String] {
    var flags: [String] = []
    if stats.coverage < 0.005 {
        flags.append("low_coverage")
    }
    if stats.corePixelCount < 500 {
        flags.append("small_sample")
    }
    if stats.stdL > 18 {
        flags.append("high_variance")
    }
    if confidence < 0.35 {
        flags.append("low_confidence")
    }
    if lowLightDetected {
        flags.append("low_light_capture")
    }
    if limitingFactor == "lighting" {
        flags.append("lighting_limited")
    } else if limitingFactor == "teeth_signal" {
        flags.append("teeth_signal_limited")
    }
    return flags
}

private func buildDisclaimer(confidence: Double, flags: [String], limitingFactor: String) -> String {
    if flags.isEmpty, confidence >= 0.6 {
        return "Local estimate from the current capture. Compare trends across multiple scans for better reliability."
    }
    if limitingFactor == "lighting" {
        return "Lighting is the main limit for this scan. Use brighter, even front lighting to improve confidence."
    }
    if limitingFactor == "teeth_signal" {
        return "Teeth visibility is the main limit for this scan. Show a fuller smile and keep teeth centered."
    }
    return "Local estimate with reduced reliability for this capture. Re-scan in brighter, even lighting and keep teeth centered to improve confidence."
}

private func buildTakeaway(score: Int, issues: [DetectedIssue], confidence: Double, limitingFactor: String) -> String {
    if confidence < 0.35 {
        if limitingFactor == "lighting" {
            return "This result is mostly limited by lighting. Retake with stronger front light for a more reliable score."
        }
        return "Capture quality is limiting precision. Retake with a wider smile, steady framing, and brighter front lighting."
    }
    if score >= 70 {
        return "Shade and brightness are in a strong range. Keep routine consistent and track weekly trends."
    }
    if issues.contains(where: { $0.key == "surface_staining" }) {
        return "Tone suggests surface staining. Consistent brushing/flossing and stain-reducing habits can help over time."
    }
    return "Result is usable for trend tracking. Repeat scans in similar lighting to compare progress more reliably."
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
                notes: ""
            )
        )
    } else if b > 17 {
        issues.append(
            DetectedIssue(
                key: "surface_staining",
                severity: "medium",
                notes: ""
            )
        )
    }

    if lightness < 54 {
        issues.append(
            DetectedIssue(
                key: "overall_brightness",
                severity: lightness < 48 ? "high" : "medium",
                notes: ""
            )
        )
    }

    if lightnessStdDev > 15 {
        issues.append(
            DetectedIssue(
                key: "tone_variation",
                severity: "medium",
                notes: ""
            )
        )
    }

    if maskCoverage < 0.009 {
        issues.append(
            DetectedIssue(
                key: "capture_quality",
                severity: "low",
                notes: ""
            )
        )
    }

    return issues
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

