import FramepebbleCore
import SwiftUI

struct CollagePhotoPicker: View {
  @Bindable var model: Workspace
  @Binding var selection: Set<UUID>
  var single = false
  var title = "Collage Sources"
  var apply: () -> Void
  @State private var query = ""
  @Environment(\.dismiss) private var dismiss
  var photos: [SourceAsset] { query.isEmpty ? model.assets : model.assets.filter {$0.name.localizedCaseInsensitiveContains(query)} }
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment:.leading) {
          Text(single ? (title == "Mosaic Reference" ? "Choose the reference to recreate. Import it into Photo Library first if needed." : "Choose a photo to place in the selected frame.") : "Choose the photos for this composition. Art collages can also use the entire library as candidates.")
            .font(.callout).foregroundStyle(.secondary).padding(.horizontal)
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
      }.searchable(text:$query,prompt:"Find a photo").navigationTitle(title + " · \(selection.count) selected").compactNavigationTitle()
        .toolbar {
          if !single {
            Menu("Select") {
              Button("Select Visible") {selection.formUnion(photos.map(\.id))}
              Button("Clear Selection") {selection=[]}
            }
          }
          Button("Cancel") {dismiss()}
          Button(single ? (title == "Mosaic Reference" ? "Use Reference" : "Use Photo") : "Use Photos") {apply()}
            .disabled(selection.isEmpty || (!single && selection.count>CollageProject.maximumCells))
        }
    }.background(.background)
    #if os(macOS)
      .frame(minWidth:600,idealWidth:800,minHeight:480,idealHeight:650)
    #endif
  }
}
