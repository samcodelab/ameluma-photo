import SwiftUI

#if os(macOS)
  import AppKit
#endif

/// Bundled guidance works offline. Public links are shown only when configured with HTTPS URLs.
struct HelpPrivacyView: View {
  let storageDirectory: URL
  @Environment(\.dismiss) private var dismiss
  @State private var document = "PrivacyPolicy"
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          Text("Ameluma Photo · Broad Frame Studio").font(.headline)
          Text(
            "Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")"
          ).font(.caption).foregroundStyle(.secondary)
          Picker("Read", selection: $document) {
            Text("Privacy policy").tag("PrivacyPolicy")
            Text("How to use").tag("Help")
          }.pickerStyle(.segmented)
          if let url = publicURL("PrivacyPolicyURL") {
            Link("Public privacy policy", destination: url)
          }
          if let url = publicURL("SupportURL") { Link("Support", destination: url) }
          ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
            if paragraph.hasPrefix("#") {
              Text(paragraph.drop(while: { $0 == "#" || $0 == " " })).font(.headline)
                .accessibilityAddTraits(.isHeader)
            } else {
              Text(paragraph).font(.body).textSelection(.enabled)
            }
          }
          #if os(macOS)
            Divider()
            Text("Local storage").font(.headline)
            Text(
              "Quit Ameluma Photo before changing its local files. Removing saved source copies can make projects unavailable. Export important results first. This does not erase originals or files saved elsewhere."
            ).font(.callout)
            Button("Show local storage in Finder", systemImage: "folder") {
              NSWorkspace.shared.activateFileViewerSelecting([storageDirectory])
            }
          #endif
        }.frame(maxWidth: 680, alignment: .leading).padding(20).frame(maxWidth: .infinity)
      }.navigationTitle("Help & Privacy").compactNavigationTitle().toolbar {
        Button("Done") { dismiss() }
      }
    }
    #if os(macOS)
      .frame(minWidth: 500, minHeight: 500)
    #endif
  }
  var paragraphs: [String] {
    guard let url = Bundle.main.url(forResource: document, withExtension: "md"),
      let text = try? String(contentsOf: url, encoding: .utf8)
    else {
      return [
        "This document could not be loaded. Please contact support using the public support link."
      ]
    }
    return text.components(separatedBy: "\n\n").filter { !$0.isEmpty }
  }
  func publicURL(_ key: String) -> URL? {
    guard let location = Bundle.main.url(forResource: "Distribution", withExtension: "plist"),
      let data = try? Data(contentsOf: location),
      let settings = try? PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: String],
      let value = settings[key], let url = URL(string: value), url.scheme == "https",
      url.host != nil
    else { return nil }
    return url
  }
}
