import Cocoa
import FlutterMacOS
import ImageIO
import NaturalLanguage
import Vision

final class MainFlutterWindow: NSWindow {
  private var ocrChannel: FlutterMethodChannel?
  private let ocrQueue = DispatchQueue(label: "com.mindpocket.mindpocket.ocr", qos: .userInitiated)
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    contentViewController = flutterViewController
    title = "MindPocket"
    contentMinSize = NSSize(width: 480, height: 600)
    setContentSize(NSSize(width: 1280, height: 800))
    center()

    RegisterGeneratedPlugins(registry: flutterViewController)
    let channel = FlutterMethodChannel(
      name: "mindpocket/ocr",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    let queue = ocrQueue
    channel.setMethodCallHandler { call, result in
      guard call.method == "recognize" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let arguments = call.arguments as? [String: Any],
            let path = arguments["path"] as? String,
            (path as NSString).isAbsolutePath else {
        result(FlutterError(
          code: "INVALID_ARGUMENT",
          message: "recognize requires an absolute image file path.",
          details: nil
        ))
        return
      }
      queue.async {
        autoreleasepool {
          do {
            let response = try recognizeImage(at: path)
            DispatchQueue.main.async { result(response) }
          } catch {
            let nativeError = error as NSError
            DispatchQueue.main.async {
              result(FlutterError(
                code: "OCR_FAILED",
                message: nativeError.localizedDescription,
                details: ["domain": nativeError.domain, "code": nativeError.code]
              ))
            }
          }
        }
      }
    }
    ocrChannel = channel

    super.awakeFromNib()
  }
}

private func recognizeImage(at path: String) throws -> [String: String] {
  let url = URL(fileURLWithPath: path)
  let attributes = try FileManager.default.attributesOfItem(atPath: path)
  guard attributes[.type] as? FileAttributeType == .typeRegular else {
    throw NSError(
      domain: "com.mindpocket.mindpocket.ocr",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: "The OCR path must refer to an existing image file."]
    )
  }
  guard FileManager.default.isReadableFile(atPath: path),
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        CGImageSourceGetCount(source) > 0 else {
    throw NSError(
      domain: "com.mindpocket.mindpocket.ocr",
      code: 2,
      userInfo: [NSLocalizedDescriptionKey: "The image could not be read or decoded."]
    )
  }

  let request = VNRecognizeTextRequest()
  request.recognitionLevel = .accurate
  request.usesLanguageCorrection = true
  request.automaticallyDetectsLanguage = true
  try VNImageRequestHandler(url: url, options: [:]).perform([request])

  let text = (request.results ?? [])
    .compactMap { $0.topCandidates(1).first?.string }
    .joined(separator: "\n")
  let languageRecognizer = NLLanguageRecognizer()
  languageRecognizer.processString(text)
  return [
    "text": text,
    "engine": "apple_vision",
    "language": languageRecognizer.dominantLanguage?.rawValue ?? "und",
  ]
}
