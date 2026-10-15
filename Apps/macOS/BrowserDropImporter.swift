import AppKit
import Foundation
import FramepebbleCore
import ImageIO
import UniformTypeIdentifiers

/// Acquisition only: every result is validated and copied by the existing shared engine.
@MainActor enum BrowserDropImporter {
  static let acceptedTypes = [UTType.fileURL, .image, .url]
  nonisolated static let maximumBytes = 25 * 1024 * 1024

  static func start(_ providers: [NSItemProvider], model: Workspace) -> Bool {
    guard !providers.isEmpty, model.importTask == nil else { return false }
    model.importing = true
    if model.fileImportTask == nil {
      model.importCompleted = 0
      model.importSkipped = 0
      model.importFailed = 0
      model.importMessage = "Receiving browser images…"
    }
    model.importTask = Task {
      defer {
        model.importing = false
        model.importTask = nil
        model.startIndexing()
      }
      model.status = "Importing dropped images…"
      for provider in providers {
        if Task.isCancelled { break }
        do {
          var fallbackURL: URL?
          if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            do {
              let url = try await providedURL(provider, type: UTType.fileURL.identifier)
              try Task.checkCancellation()
              if url.isFileURL {
                await model.importURLs([url])
                continue
              }
              fallbackURL = url
            } catch is CancellationError { throw CancellationError() } catch
            { /* Some browsers offer image bytes instead of the advertised file URL. */  }
          }
          // Prefer browser-supplied image bytes: no web request when an image is available.
          var imageData: Data?
          for type in provider.registeredTypeIdentifiers
          where UTType(type)?.conforms(to: .image) == true {
            do {
              imageData = try await data(provider, type: type)
              break
            } catch is CancellationError { throw CancellationError() } catch { continue }
          }
          if let imageData {
            let name = try imageName(imageData, suggested: provider.suggestedName)
            try Task.checkCancellation()
            await model.importData(imageData, name: name)
          } else if fallbackURL != nil
            || provider.hasItemConformingToTypeIdentifier(UTType.url.identifier)
          {
            let url: URL
            if let fallbackURL {
              url = fallbackURL
            } else {
              url = try await providedURL(provider, type: UTType.url.identifier)
            }
            if url.isFileURL {
              await model.importURLs([url])
              continue
            }
            let downloaded = try await WebImageDownload.fetch(url)
            let name = try imageName(downloaded, suggested: url.lastPathComponent)
            try Task.checkCancellation()
            await model.importData(downloaded, name: name)
          } else {
            throw DropError.invalid
          }
        } catch is CancellationError {
          model.status = "Import cancelled. Imported images are retained."
          break
        } catch { model.issues.append("Dropped image: \(error.localizedDescription)") }
      }
      if Task.isCancelled { model.status = "Import cancelled. Imported images are retained." }
    }
    return true
  }

  static func providedURL(_ provider: NSItemProvider, type: String) async throws -> URL {
    if provider.canLoadObject(ofClass: NSURL.self) {
      let transfer = ProviderTransfer<URL>()
      return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation {
          (continuation: CheckedContinuation<URL, Error>) in
          transfer.begin(continuation)
          let progress = provider.loadObject(ofClass: NSURL.self) { object, error in
            if let url = object as? URL {
              transfer.complete(.success(url))
            } else {
              transfer.complete(.failure(error ?? DropError.invalid))
            }
          }
          transfer.install(progress)
        }
      } onCancel: {
        transfer.cancel()
      }
    }
    let bytes = try await data(provider, type: type)
    guard let url = URL(dataRepresentation: bytes, relativeTo: nil) else { throw DropError.invalid }
    return url
  }

  static func data(_ provider: NSItemProvider, type: String) async throws -> Data {
    let transfer = ProviderTransfer<Data>()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Data, Error>) in
        transfer.begin(continuation)
        let progress = provider.loadDataRepresentation(forTypeIdentifier: type) { bytes, error in
          if let bytes {
            transfer.complete(.success(bytes))
          } else {
            transfer.complete(.failure(error ?? DropError.invalid))
          }
        }
        transfer.install(progress)
      }
    } onCancel: {
      transfer.cancel()
    }
  }

  static func imageName(_ bytes: Data, suggested: String?) throws -> String {
    guard !bytes.isEmpty, bytes.count <= maximumBytes else { throw DropError.tooLarge }
    guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
      CGImageSourceGetStatus(source) == .statusComplete,
      let identifier = CGImageSourceGetType(source),
      let type = UTType(identifier as String),
      ImageProcessor.importTypes.contains(where: { $0.identifier == type.identifier })
    else { throw DropError.invalid }
    let base = ((suggested ?? "Browser image") as NSString).lastPathComponent
    let stem = (base as NSString).deletingPathExtension
    return String((stem.isEmpty ? "Browser image" : stem).prefix(100)) + "."
      + (type.preferredFilenameExtension ?? "img")
  }
}

private final class ProviderTransfer<Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var progress: Progress?
  private var continuation: CheckedContinuation<Value, Error>?
  private var cancelled = false
  func begin(_ continuation: CheckedContinuation<Value, Error>) {
    lock.lock()
    if cancelled {
      lock.unlock()
      continuation.resume(throwing: CancellationError())
      return
    }
    self.continuation = continuation
    lock.unlock()
  }
  func complete(_ result: Result<Value, Error>) {
    lock.lock()
    let continuation = continuation
    self.continuation = nil
    lock.unlock()
    continuation?.resume(with: result)
  }
  func install(_ progress: Progress) {
    lock.lock()
    self.progress = progress
    let shouldCancel = cancelled
    lock.unlock()
    if shouldCancel { progress.cancel() }
  }
  func cancel() {
    lock.lock()
    cancelled = true
    let progress = progress
    let continuation = continuation
    self.continuation = nil
    lock.unlock()
    continuation?.resume(throwing: CancellationError())
    progress?.cancel()
  }
}

enum DropError: LocalizedError {
  case invalid, tooLarge, insecureURL, response
  var errorDescription: String? {
    switch self {
    case .invalid:
      "This drop does not contain a supported image. Drag the image itself, or save it and import the file."
    case .tooLarge:
      "Browser images must be 25 MB or smaller. Save larger images to disk and import the file."
    case .insecureURL:
      "Only HTTPS image links without embedded login credentials can be downloaded. Save this image in the browser, then import the file."
    case .response:
      "The website did not return an accessible image. Images requiring a browser login must be saved in the browser first."
    }
  }
}

/// The only app network path. No uploads, browser cookies, saved credentials or cache.
enum WebImageDownload {
  static func permits(_ url: URL) -> Bool {
    url.scheme?.lowercased() == "https" && url.host != nil && url.user == nil && url.password == nil
  }
  static func validate(_ response: URLResponse, maximumBytes: Int) throws {
    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
      let url = http.url, permits(url)
    else { throw DropError.response }
    if response.expectedContentLength > Int64(maximumBytes) { throw DropError.tooLarge }
    // MIME is advisory; actual ImageIO validation follows the bounded download.
  }
  static func append(_ byte: UInt8, to bytes: inout Data, limit: Int) throws {
    guard bytes.count < limit else { throw DropError.tooLarge }
    bytes.append(byte)
  }
  static func fetch(
    _ url: URL, configuration: URLSessionConfiguration = .ephemeral,
    maximumBytes: Int = BrowserDropImporter.maximumBytes
  ) async throws -> Data {
    guard permits(url) else { throw DropError.insecureURL }
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCredentialStorage = nil
    configuration.urlCache = nil
    configuration.timeoutIntervalForRequest = 20
    configuration.timeoutIntervalForResource = 30
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
    request.setValue("image/*", forHTTPHeaderField: "Accept")
    let (stream, response) = try await session.bytes(for: request, delegate: WebImageRedirects())
    try validate(response, maximumBytes: maximumBytes)
    var bytes = Data()
    for try await byte in stream {
      try Task.checkCancellation()
      try append(byte, to: &bytes, limit: maximumBytes)
    }
    return bytes
  }
}

private final class WebImageRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  private var redirects = 0  // URLSession serialises its delegate callbacks.
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    redirects += 1
    guard redirects <= 5, let url = request.url, WebImageDownload.permits(url) else {
      completionHandler(nil)
      return
    }
    completionHandler(request)
  }
  func urlSession(
    _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
    completionHandler:
      @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
      completionHandler(.performDefaultHandling, nil)
    } else {
      completionHandler(.cancelAuthenticationChallenge, nil)
    }
  }
}
