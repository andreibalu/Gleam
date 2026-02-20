import CoreImage
import Foundation
import UIKit

struct LocalTeethAnalyzer {

  // MARK: - Public

  static func analyze(imageData: Data, teethMatte: CIImage) -> ScanResult {
    guard let ciPhoto = CIImage(data: imageData) else {
      return fallbackResult
    }

    let context = CIContext(options: [.useSoftwareRenderer: false])

    let scaledMatte = scaleMatte(teethMatte, toMatch: ciPhoto)
    let maskedPixels = extractTeethPixels(
      photo: ciPhoto, matte: scaledMatte, context: context
    )

    guard !maskedPixels.isEmpty else {
      return fallbackResult
    }

    let (meanL, meanA, meanB) = averageLAB(pixels: maskedPixels)
    let whitenessScore = computeWhitenessScore(meanL: meanL)
    let shade = nearestVITAShade(l: meanL, a: meanA, b: meanB)
    let confidence = computeConfidence(
      pixelCount: maskedPixels.count,
      imageSize: ciPhoto.extent.size
    )
    let takeaway = templateTakeaway(score: whitenessScore)

    return ScanResult(
      whitenessScore: whitenessScore,
      shade: shade,
      detectedIssues: [],
      confidence: confidence,
      referralNeeded: false,
      disclaimer: "This is an estimate based on your photo's lighting. For a clinical shade match, visit your dentist.",
      personalTakeaway: takeaway
    )
  }

  // MARK: - Matte Scaling

  private static func scaleMatte(
    _ matte: CIImage, toMatch photo: CIImage
  ) -> CIImage {
    let scaleX = photo.extent.width / matte.extent.width
    let scaleY = photo.extent.height / matte.extent.height
    return matte.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
  }

  // MARK: - Pixel Extraction

  private struct RGBPixel {
    let r: Double
    let g: Double
    let b: Double
  }

  private static func extractTeethPixels(
    photo: CIImage, matte: CIImage, context: CIContext
  ) -> [RGBPixel] {
    let width = Int(photo.extent.width)
    let height = Int(photo.extent.height)

    guard width > 0, height > 0 else { return [] }

    let matteWidth = Int(matte.extent.width)
    let matteHeight = Int(matte.extent.height)
    var matteBuffer = [UInt8](repeating: 0, count: matteWidth * matteHeight)
    context.render(
      matte,
      toBitmap: &matteBuffer,
      rowBytes: matteWidth,
      bounds: matte.extent,
      format: .L8,
      colorSpace: nil
    )

    let rgbaCount = width * height * 4
    var photoBuffer = [UInt8](repeating: 0, count: rgbaCount)
    context.render(
      photo,
      toBitmap: &photoBuffer,
      rowBytes: width * 4,
      bounds: photo.extent,
      format: .RGBA8,
      colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
    )

    let matteThreshold: UInt8 = 128
    var pixels: [RGBPixel] = []
    pixels.reserveCapacity(width * height / 10)

    for y in 0 ..< min(height, matteHeight) {
      for x in 0 ..< min(width, matteWidth) {
        let matteIndex = y * matteWidth + x
        guard matteBuffer[matteIndex] > matteThreshold else { continue }
        let photoIndex = (y * width + x) * 4
        let r = Double(photoBuffer[photoIndex]) / 255.0
        let g = Double(photoBuffer[photoIndex + 1]) / 255.0
        let b = Double(photoBuffer[photoIndex + 2]) / 255.0
        pixels.append(RGBPixel(r: r, g: g, b: b))
      }
    }

    return pixels
  }

  // MARK: - sRGB -> CIELAB

  private static func averageLAB(pixels: [RGBPixel]) -> (Double, Double, Double) {
    var sumL = 0.0, sumA = 0.0, sumB = 0.0
    for px in pixels {
      let (l, a, b) = srgbToLab(r: px.r, g: px.g, b: px.b)
      sumL += l
      sumA += a
      sumB += b
    }
    let n = Double(pixels.count)
    return (sumL / n, sumA / n, sumB / n)
  }

  private static func srgbToLab(r: Double, g: Double, b: Double) -> (Double, Double, Double) {
    let rLin = linearize(r)
    let gLin = linearize(g)
    let bLin = linearize(b)

    // sRGB -> XYZ (D65)
    let x = rLin * 0.4124564 + gLin * 0.3575761 + bLin * 0.1804375
    let y = rLin * 0.2126729 + gLin * 0.7151522 + bLin * 0.0721750
    let z = rLin * 0.0193339 + gLin * 0.1191920 + bLin * 0.9503041

    // D65 reference white
    let xn = 0.95047, yn = 1.0, zn = 1.08883
    let fx = labF(x / xn)
    let fy = labF(y / yn)
    let fz = labF(z / zn)

    let l = 116.0 * fy - 16.0
    let a = 500.0 * (fx - fy)
    let bVal = 200.0 * (fy - fz)
    return (l, a, bVal)
  }

  private static func linearize(_ c: Double) -> Double {
    c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
  }

  private static func labF(_ t: Double) -> Double {
    let delta: Double = 6.0 / 29.0
    return t > delta * delta * delta
      ? pow(t, 1.0 / 3.0)
      : t / (3.0 * delta * delta) + 4.0 / 29.0
  }

  // MARK: - Whiteness Score

  private static func computeWhitenessScore(meanL: Double) -> Int {
    let score = (meanL - 40.0) * (100.0 / 55.0)
    return max(0, min(100, Int(score)))
  }

  // MARK: - VITA Shade Mapping (CIE76 Delta-E)

  private struct VITAReference {
    let code: String
    let l: Double, a: Double, b: Double
  }

  private static let vitaReferences: [VITAReference] = [
    VITAReference(code: "A1", l: 79.0, a: 0.5, b: 16.0),
    VITAReference(code: "A2", l: 76.0, a: 1.0, b: 19.0),
    VITAReference(code: "A3", l: 73.5, a: 2.0, b: 22.0),
    VITAReference(code: "B1", l: 78.0, a: -1.0, b: 13.0),
    VITAReference(code: "B2", l: 75.0, a: 0.0, b: 17.0),
    VITAReference(code: "B3", l: 72.0, a: 1.0, b: 20.0),
    VITAReference(code: "C1", l: 77.0, a: 0.0, b: 14.0),
    VITAReference(code: "C2", l: 74.0, a: 1.5, b: 18.0),
    VITAReference(code: "C3", l: 70.0, a: 2.5, b: 22.0),
    VITAReference(code: "D2", l: 74.5, a: 1.0, b: 16.0),
    VITAReference(code: "D3", l: 71.0, a: 2.0, b: 20.0),
    VITAReference(code: "D4", l: 68.0, a: 3.0, b: 24.0),
  ]

  private static func nearestVITAShade(l: Double, a: Double, b: Double) -> String {
    var bestCode = "A2"
    var bestDist = Double.greatestFiniteMagnitude
    for ref in vitaReferences {
      let dL = l - ref.l
      let dA = a - ref.a
      let dB = b - ref.b
      let dist = sqrt(dL * dL + dA * dA + dB * dB)
      if dist < bestDist {
        bestDist = dist
        bestCode = ref.code
      }
    }
    return bestCode
  }

  // MARK: - Confidence

  private static func computeConfidence(pixelCount: Int, imageSize: CGSize) -> Double {
    let totalPixels = imageSize.width * imageSize.height
    guard totalPixels > 0 else { return 0.3 }
    // Teeth typically occupy 1-5% of a selfie. Scale confidence accordingly.
    let ratio = Double(pixelCount) / totalPixels
    if ratio < 0.005 { return 0.3 }
    if ratio > 0.04 { return 0.92 }
    return 0.3 + (ratio - 0.005) / (0.04 - 0.005) * 0.62
  }

  // MARK: - Template Takeaway

  private static func templateTakeaway(score: Int) -> String {
    switch score {
    case 80...:
      return "Your smile is looking bright and radiant! Keep up the great routine."
    case 60..<80:
      return "Your teeth are in good shape. A few tweaks to your routine could make them even brighter."
    case 40..<60:
      return "There's room for improvement. Consider whitening products or adjusting your diet for a brighter smile."
    default:
      return "Your teeth could use some attention. A dental visit and consistent care will help improve your smile."
    }
  }

  // MARK: - Fallback

  private static var fallbackResult: ScanResult {
    ScanResult(
      whitenessScore: 50,
      shade: "A2",
      detectedIssues: [],
      confidence: 0.2,
      referralNeeded: false,
      disclaimer: "Unable to fully analyze teeth region. Results may be inaccurate.",
      personalTakeaway: "We couldn't get a clear read on your teeth. Try again with better lighting."
    )
  }
}
