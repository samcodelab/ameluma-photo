import FramepebbleCore
import SwiftUI

struct StickerPicker: View {
  let choose: (Sticker) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var collection: String
  @Environment(\.dynamicTypeSize) private var typeSize
  init(collection: String = "Dress Up", choose: @escaping (Sticker) -> Void) { self.choose = choose; _collection = State(initialValue: collection) }
  @State private var query = ""
  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 180 : 100), spacing: 12)], spacing: 16) {
          ForEach(StickerCatalog.stickers.filter { $0.collection == collection && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }) { sticker in
            Button { choose(sticker); dismiss() } label: {
              VStack(spacing: 6) {
                Canvas { context, size in
                  let width = min(size.width-8, (size.height-8)*sticker.aspectRatio)
                  let height = width/sticker.aspectRatio
                  context.withCGContext { cg in StickerRenderer.draw(sticker, in: CGRect(x:(size.width-width)/2,y:(size.height-height)/2,width:width,height:height), context:cg) }
                }.frame(height: 78).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius:8))
                Text(sticker.name).font(.caption).foregroundStyle(.primary).lineLimit(2)
              }
            }.buttonStyle(.plain).accessibilityLabel("Add " + sticker.name)
          }
        }.padding(16)
      }.searchable(text: $query, prompt: "Find a sticker")
        .safeAreaInset(edge: .top) {
          Group {
            if typeSize.isAccessibilitySize { collectionPicker.pickerStyle(.menu) }
            else { collectionPicker.pickerStyle(.segmented) }
          }.padding(12).background(.bar)
        }
        .navigationTitle("Stickers").compactNavigationTitle()
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
    }
    #if os(macOS)
    .frame(minWidth: 420, idealWidth: 600, maxWidth: 760, minHeight: 440, idealHeight: 620, maxHeight: 800)
    #endif
  }
  var collectionPicker: some View {
    Picker("Sticker collection", selection: $collection) {
      ForEach(StickerCatalog.collections, id: \.self) { Text($0).tag($0) }
    }
  }
}
