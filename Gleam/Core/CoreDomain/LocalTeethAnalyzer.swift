import CoreImage
import Foundation
import UIKit

struct LocalTeethAnalyzer {
    private struct LabColor {
        let l: Double
        let a: Double
        let b: Double
    }

    private struct TeethStatistics {
        let meanLab: LabColor
        let teethPixelCount: Int
        let totalPixelCount: Int
    }

    private static let disclaimer = "Not a medical diagnosis. Consult a dentist for concerns."
    private static let matteThreshold: UInt8 = 127
    private static let expectedTeethCoverage: Double = 0.08
    private static let ciContext = CIContext(
        options: [
            .workingColorSpace: NSNull(),
            .outputColorSpace: NSNull()
        ]
    )
    private static let vitaLabReferences: [String: LabColor] = [
        "A1": LabColor(l: 83.0, a: 1.2, b: 18.0),
        "A2": LabColor(l: 79.5, a: 2.2, b: 22.0),
        "A3": LabColor(l: 75.5, a: 3.1, b: 27.0),
        "B1": LabColor(l: 85.0, a: -0.2, b: 16.0),
        "B2": LabColor(l: 81.0, a: 0.8, b: 21.0),
        "B3": LabColor(l: 77.0, a: 1.6, b: 25.0),
        "C1": LabColor(l: 78.5, a: 0.5, b: 16.5),
        "C2": LabColor(l: 74.0, a: 1.1, b: 20.0),
        "C3": LabColor(l: 69.5, a: 1.7, b: 24.0),
        "D2": LabColor(l: 76.0, a: 0.6, b: 18.5),
        "D3": LabColor(l: 71.5, a: 1.3, b: 22.0),
        "D4": LabColor(l: 66.5, a: 2.0, b: 26.5)
    ]

    static func analyze(imageData: Data, teethMatte: CIImage) -> ScanResult {
        guard let statistics = extractStatistics(imageData: imageData, teethMatte: teethMatte) else {
            let fallbackScore = 55
            return ScanResult(
                whitenessScore: fallbackScore,
                shade: "A3",
                detectedIssues: [],
                confidence: 0.35,
                referralNeeded: false,
                disclaimer: disclaimer,
                personalTakeaway: ""
            )
        }

        let rawScore = Int((statistics.meanLab.l - 40.0) * (100.0 / 55.0))
        let whitenessScore = clamp(rawScore, min: 0, max: 100)

        let matchedShade = nearestShade(for: statistics.meanLab)
        let observedCoverage = Double(statistics.teethPixelCount) / Double(max(statistics.totalPixelCount, 1))
        let normalizedCoverage = clamp(observedCoverage / expectedTeethCoverage, min: 0.0, max: 1.0)
        let confidence = clamp(0.35 + normalizedCoverage * 0.55, min: 0.35, max: 0.9)

        return ScanResult(
            whitenessScore: whitenessScore,
            shade: matchedShade,
            detectedIssues: [],
            confidence: confidence,
            referralNeeded: false,
            disclaimer: disclaimer,
            personalTakeaway: ""
        )
    }

    private static func extractStatistics(imageData: Data, teethMatte: CIImage) -> TeethStatistics? {
        guard let image = UIImage(data: imageData), let imageCG = image.cgImage else {
            return nil
        }

        let width = imageCG.width
        let height = imageCG.height
        guard width > 0, height > 0 else { return nil }

        var imagePixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let imageContext = CGContext(
            data: &imagePixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return nil
        }

        imageContext.interpolationQuality = .high
        imageContext.draw(imageCG, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let matteCG = ciContext.createCGImage(teethMatte, from: teethMatte.extent) else {
            return nil
        }

        var mattePixels = [UInt8](repeating: 0, count: width * height)
        guard let matteContext = CGContext(
            data: &mattePixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        matteContext.interpolationQuality = .high
        matteContext.draw(matteCG, in: CGRect(x: 0, y: 0, width: width, height: height))

        var lSum = 0.0
        var aSum = 0.0
        var bSum = 0.0
        var count = 0

        for pixelIndex in 0..<(width * height) {
            guard mattePixels[pixelIndex] > matteThreshold else { continue }
            let offset = pixelIndex * 4

            let red = Double(imagePixels[offset]) / 255.0
            let green = Double(imagePixels[offset + 1]) / 255.0
            let blue = Double(imagePixels[offset + 2]) / 255.0
            let lab = rgbToLab(red: red, green: green, blue: blue)
            lSum += lab.l
            aSum += lab.a
            bSum += lab.b
            count += 1
        }

        guard count > 0 else { return nil }
        let meanLab = LabColor(
            l: lSum / Double(count),
            a: aSum / Double(count),
            b: bSum / Double(count)
        )
        return TeethStatistics(meanLab: meanLab, teethPixelCount: count, totalPixelCount: width * height)
    }

    private static func nearestShade(for lab: LabColor) -> String {
        vitaLabReferences.min { lhs, rhs in
            deltaE(lab, lhs.value) < deltaE(lab, rhs.value)
        }?.key ?? "A3"
    }

    private static func deltaE(_ lhs: LabColor, _ rhs: LabColor) -> Double {
        let dl = lhs.l - rhs.l
        let da = lhs.a - rhs.a
        let db = lhs.b - rhs.b
        return (dl * dl + da * da + db * db).squareRoot()
    }

    private static func rgbToLab(red: Double, green: Double, blue: Double) -> LabColor {
        let linearRed = linearizedSRGB(red)
        let linearGreen = linearizedSRGB(green)
        let linearBlue = linearizedSRGB(blue)

        let x = linearRed * 0.4124564 + linearGreen * 0.3575761 + linearBlue * 0.1804375
        let y = linearRed * 0.2126729 + linearGreen * 0.7151522 + linearBlue * 0.0721750
        let z = linearRed * 0.0193339 + linearGreen * 0.1191920 + linearBlue * 0.9503041

        let xn = 0.95047
        let yn = 1.00000
        let zn = 1.08883

        let fx = xyzToLabComponent(x / xn)
        let fy = xyzToLabComponent(y / yn)
        let fz = xyzToLabComponent(z / zn)

        return LabColor(
            l: max(0, 116.0 * fy - 16.0),
            a: 500.0 * (fx - fy),
            b: 200.0 * (fy - fz)
        )
    }

    private static func linearizedSRGB(_ value: Double) -> Double {
        if value <= 0.04045 {
            return value / 12.92
        }
        return pow((value + 0.055) / 1.055, 2.4)
    }

    private static func xyzToLabComponent(_ value: Double) -> Double {
        let delta = 6.0 / 29.0
        let deltaCubed = delta * delta * delta
        if value > deltaCubed {
            return cbrt(value)
        }
        return value / (3.0 * delta * delta) + (4.0 / 29.0)
    }

    private static func clamp<T: Comparable>(_ value: T, min minValue: T, max maxValue: T) -> T {
        Swift.min(Swift.max(value, minValue), maxValue)
    }
}
