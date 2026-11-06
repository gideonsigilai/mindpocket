import Flutter
import Photos
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var screenshots: ScreenshotChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    // Includes receive_sharing_intent; its initial-media call is valid even
    // without a share extension. This target does not advertise a share sheet.
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MindPocketScreenshots") else {
      preconditionFailure("The Flutter screenshot registrar is unavailable")
    }
    screenshots = ScreenshotChannel(messenger: registrar.messenger())
  }
}

/// Permission presentation and Flutter replies stay on main; PhotoKit fetches,
/// metadata preparation and file IO run on a serial background queue.
private final class ScreenshotChannel {
  private let channel: FlutterMethodChannel
  private let worker = DispatchQueue(label: "com.mindpocket.screenshots", qos: .userInitiated)
  private var permissionRequests: [FlutterResult] = []
  // A stable snapshot for each paginated scan; scoped to the worker queue.
  private var snapshot: [PHAsset]?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "mindpocket/screenshots", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "permission":
        result(Self.hasPermission)
      case "requestPermission":
        self.requestPermission(result)
      case "count":
        self.perform(result) { self.screenshotFetch().count }
      case "list":
        let arguments = call.arguments as? [String: Any] ?? [:]
        let afterID = arguments["afterId"] as? String
        let limit = (arguments["limit"] as? NSNumber)?.intValue ?? 500
        guard (1...500).contains(limit) else {
          result(FlutterError(code: "bad_args", message: "limit must be between 1 and 500", details: nil))
          return
        }
        self.perform(result) {
          if afterID == nil { self.snapshot = self.screenshotAssets() }
          let assets = self.snapshot ?? self.screenshotAssets()
          var start = 0
          var end = assets.count
          if let afterID {
            while start < end {
              let middle = start + (end - start) / 2
              if assets[middle].localIdentifier.compare(afterID, options: .literal) == .orderedDescending {
                end = middle
              } else {
                start = middle + 1
              }
            }
          }
          end = min(start + limit, assets.count)
          var rows: [[String: Any]] = []
          rows.reserveCapacity(end - start)
          for index in start..<end {
            rows.append(Self.metadata(assets[index]))
          }
          if rows.isEmpty { self.snapshot = nil }
          return rows
        }
      case "copy":
        let arguments = call.arguments as? [String: Any] ?? [:]
        guard let identifier = arguments["contentUri"] as? String,
          identifier.hasPrefix("ph://"),
          let destination = arguments["destination"] as? String,
          !destination.isEmpty else {
          result(FlutterError(code: "bad_args", message: "A Photos URI and destination are required", details: nil))
          return
        }
        self.copy(identifier: String(identifier.dropFirst(5)), destination: destination, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static var hasPermission: Bool {
    let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    return status == .authorized || status == .limited
  }

  private func requestPermission(_ result: @escaping FlutterResult) {
    if Self.hasPermission {
      result(true)
      return
    }
    permissionRequests.append(result)
    guard permissionRequests.count == 1 else { return }
    PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] _ in
      DispatchQueue.main.async {
        guard let self else { return }
        let requests = self.permissionRequests
        self.permissionRequests.removeAll()
        requests.forEach { $0(Self.hasPermission) }
      }
    }
  }

  private func perform(_ result: @escaping FlutterResult, work: @escaping () -> Any) {
    worker.async {
      guard Self.hasPermission else {
        Self.reply(result, FlutterError(code: "permission_denied", message: "Screenshot access was not granted", details: nil))
        return
      }
      let value = autoreleasepool(invoking: work)
      Self.reply(result, value)
    }
  }

  private func screenshotFetch() -> PHFetchResult<PHAsset> {
    let albums = PHAssetCollection.fetchAssetCollections(
      with: .smartAlbum,
      subtype: .smartAlbumScreenshots,
      options: nil
    )
    let options = PHFetchOptions()
    options.predicate = NSPredicate(
      format: "(mediaSubtype & %d) != 0",
      Int(PHAssetMediaSubtype.photoScreenshot.rawValue)
    )
    // Limited access may hide the smart album itself. The fallback still fetches
    // only authorized screenshot assets, never arbitrary gallery images.
    if let album = albums.firstObject {
      return PHAsset.fetchAssets(in: album, options: options)
    }
    return PHAsset.fetchAssets(with: .image, options: options)
  }

  private func screenshotAssets() -> [PHAsset] {
    let fetched = screenshotFetch()
    var assets: [PHAsset] = []
    assets.reserveCapacity(fetched.count)
    fetched.enumerateObjects { asset, _, _ in assets.append(asset) }
    assets.sort {
      $0.localIdentifier.compare($1.localIdentifier, options: .literal) == .orderedAscending
    }
    return assets
  }

  private static func resource(for asset: PHAsset) -> PHAssetResource? {
    PHAssetResource.assetResources(for: asset).first { $0.type == .photo }
  }

  private static func metadata(_ asset: PHAsset) -> [String: Any] {
    let resource = resource(for: asset)
    let mime = resource.flatMap { UTType($0.uniformTypeIdentifier)?.preferredMIMEType } ?? "image/png"
    return [
      "id": asset.localIdentifier,
      "name": resource?.originalFilename ?? "",
      "contentUri": "ph://\(asset.localIdentifier)",
      "takenAt": Int64((asset.creationDate?.timeIntervalSince1970 ?? 0) * 1000),
      "width": asset.pixelWidth,
      "height": asset.pixelHeight,
      // PhotoKit has no public byte-size property. The importer validates the
      // actual copied file size; do not use unsupported KVC on PHAssetResource.
      "size": 0,
      "bucket": "Screenshots",
      "mimeType": mime,
    ]
  }

  private func copy(identifier: String, destination: String, result: @escaping FlutterResult) {
    worker.async {
      guard Self.hasPermission else {
        Self.reply(result, FlutterError(code: "permission_denied", message: "Screenshot access was not granted", details: nil))
        return
      }
      let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
      guard let asset = assets.firstObject,
        asset.mediaSubtypes.contains(.photoScreenshot),
        let resource = Self.resource(for: asset) else {
        Self.reply(result, FlutterError(code: "copy_failed", message: "The screenshot is no longer available", details: nil))
        return
      }
      let url = URL(fileURLWithPath: destination).standardizedFileURL
      guard url.path.hasPrefix(NSHomeDirectory() + "/") else {
        Self.reply(result, FlutterError(code: "bad_args", message: "The destination must be inside app storage", details: nil))
        return
      }
      do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
          try FileManager.default.removeItem(at: url)
        }
      } catch {
        Self.reply(result, FlutterError(code: "copy_failed", message: error.localizedDescription, details: nil))
        return
      }
      let options = PHAssetResourceRequestOptions()
      options.isNetworkAccessAllowed = true
      PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options) { error in
        if let error {
          Self.reply(result, FlutterError(code: "copy_failed", message: error.localizedDescription, details: nil))
        } else {
          Self.reply(result, true)
        }
      }
    }
  }

  private static func reply(_ result: @escaping FlutterResult, _ value: Any) {
    DispatchQueue.main.async { result(value) }
  }
}
