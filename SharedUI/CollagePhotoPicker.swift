import FramepebbleCore
import SwiftUI
import UniformTypeIdentifiers

struct CollagePhotoPicker: View {
  @Bindable var model: Workspace
  @Binding var selection: Set<UUID>
  var single = false
  var title = "Collage Sources"
  var apply: () -> Void
  @State private var query = ""
  @State private var filter = WorkspaceFilter()
  @State private var importing = false
  @State private var choosingFiles = false
  @State private var importMessage: String?
  @Environment(\.dismiss) private var dismiss
  var photos: [SourceAsset] {
    let visible = filter.apply(to: model.workspaceAssets, information: model.photoInfo)
    return query.isEmpty ? visible : visible.filter { $0.name.localizedCaseInsensitiveContains(query) }
  }
  var hiddenSelectionCount: Int { selection.subtracting(Set(photos.map(\.id))).count }
  var formats: [String] { Set(model.photoInfo.values.map(\.format)).sorted() }
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment:.leading) {
          Text(single ? (title == "Mosaic Reference" ? "Choose the reference to recreate, or add a photo from Files." : "Choose a photo to place in the selected frame.") : "Choose the photos for this composition. Art collages can also use the entire workspace as candidates.")
            .font(.callout).foregroundStyle(.secondary).padding(.horizontal)
          HStack {
            filterMenu
            Spacer()
            Text("\(selection.count) selected" + (hiddenSelectionCount == 0 ? "" : " · \(hiddenSelectionCount) hidden"))
              .font(.caption).foregroundStyle(.secondary)
          }.padding(.horizontal)
          if !single && selection.count > CollageProject.maximumCells {
            Text("Choose at most \(CollageProject.maximumCells) photos.").font(.caption).foregroundStyle(.red).padding(.horizontal)
          }
          if importing { ProgressView("Adding photos…").padding(.horizontal) }
          if let importMessage { Text(importMessage).font(.caption).foregroundStyle(.secondary).padding(.horizontal) }
          if photos.isEmpty {
            ContentUnavailableView {
              Label(model.workspaceAssets.isEmpty ? "Add photos to choose from" : "No matching photos", systemImage: "photo.on.rectangle")
            } description: {
              Text(model.workspaceAssets.isEmpty ? "Add photos from Files without leaving this composition." : "Your selected photos are retained. Clear the search or filters to see more.")
            } actions: {
              if !model.workspaceAssets.isEmpty { Button("Clear Search & Filters") { query = ""; filter = WorkspaceFilter() } }
              Button("Add from Files…", systemImage: "folder.badge.plus") { choosingFiles = true }.disabled(importing)
            }
          }
          LazyVGrid(columns:[GridItem(.adaptive(minimum:140))],spacing:12) {
            ForEach(photos) { asset in
              Button {
                if single { selection=[asset.id] }
                else if !selection.insert(asset.id).inserted { selection.remove(asset.id) }
              } label: {
                VStack(alignment:.leading) {
                  FramingSurface(model:model,asset:asset,interactive:false,maximum:200).frame(height:120)
                    .overlay(alignment:.topTrailing) {
                      Image(systemName:selection.contains(asset.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title2).foregroundStyle(selection.contains(asset.id) ? Color.accentColor : Color.secondary)
                        .padding(6).background(.regularMaterial,in:Circle()).padding(4)
                    }
                  Text(asset.name).font(.caption).lineLimit(2)
                }.padding(6).background(selection.contains(asset.id) ? Color.accentColor.opacity(0.12) : .clear,in:RoundedRectangle(cornerRadius:8))
              }.buttonStyle(.plain).draggable(asset.id.uuidString).accessibilityLabel(asset.name).accessibilityValue(selection.contains(asset.id) ? "Selected" : "Not selected")
            }
          }.padding()
        }
      }.searchable(text:$query,prompt:"Find a photo").navigationTitle(title).compactNavigationTitle()
        .toolbar {
          if !single {
            Menu("Select") {
              Button("Select Visible") {selection.formUnion(photos.map(\.id))}
              Button("Clear Selection") {selection=[]}
            }
          }
          Button("Add from Files…", systemImage: "folder.badge.plus") { choosingFiles = true }.disabled(importing)
          Button("Cancel") {dismiss()}
          Button(single ? (title == "Mosaic Reference" ? "Use Reference" : "Use Photo") : "Use Photos") {apply()}
            .disabled(importing || selection.isEmpty || (!single && selection.count>CollageProject.maximumCells))
        }
    }.background(.background)
      .fileImporter(isPresented: $choosingFiles, allowedContentTypes: ImageProcessor.importTypes, allowsMultipleSelection: !single) { result in
        switch result {
        case .success(let urls):
          importing = true; importMessage = nil
          Task {
            await model.importURLs(urls)
            importing = false; importMessage = model.status
            query = ""; filter = WorkspaceFilter()
          }
        case .failure(let error): importMessage = "Could not add photos: " + error.localizedDescription
        }
      }
    #if os(macOS)
      .frame(minWidth:600,idealWidth:800,minHeight:480,idealHeight:650)
    #endif
  }
  var filterMenu: some View {
    Menu(filter.isActive ? "Filters On" : "Filters", systemImage: "line.3.horizontal.decrease") {
      Picker("Date", selection: $filter.period) {
        ForEach(WorkspaceFilter.Period.allCases.filter { $0 != .custom }, id: \.self) { Text($0.rawValue).tag($0) }
      }
      Picker("Orientation", selection: $filter.orientation) {
        ForEach(WorkspaceFilter.Orientation.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }
      Picker("Format", selection: $filter.format) {
        Text("Any format").tag("")
        ForEach(formats, id: \.self) { format in Text(UTType(format)?.localizedDescription ?? format).tag(format) }
      }
      Picker("Sort", selection: $filter.sort) {
        ForEach(WorkspaceFilter.Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }
      if filter.isActive { Button("Clear Filters") { filter = WorkspaceFilter() } }
    }.accessibilityLabel(filter.isActive ? "Photo filters active" : "Filter photos")
  }

}
