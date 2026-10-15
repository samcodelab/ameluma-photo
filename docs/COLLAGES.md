# Collages, shape art and reference photomosaics

Ameluma Photo keeps multiple editable collage compositions in the same project and shared photo library. Mac/iPad show closable collage tabs; iPhone uses Open Collages. New Collage creates a separate composition. Rename changes its name. Closing a tab retains its saved composition in Your Collages in the Layout Gallery. Undo/Redo is independent per composition during the app session; opening a saved project restores compositions and open tabs but starts new in-memory histories.

## Layout gallery

74 algorithmic layouts cover square, landscape and portrait grids, feature-left/right/top/bottom editorial arrangements, rows/strips, brickwork and pinboards. Search and category filtering help locate a layout. The coloured previews are arrangement diagrams, not stock-photo samples. Choosing a card starts a new collage; its context menu can apply the layout to the current composition. Existing cell crop/shape intent is retained for matching source occurrences. Explicit quick-layout selection can rearrange cells again. Templates support variable photo counts; long strips with very many photos necessarily produce small tiles.

Source and reference selection use lazy thumbnail grids so identically named imports remain distinguishable. A selected tile can be dragged/pinched to reframe or adjusted numerically. Large compositions use one canvas hit-test/gesture surface rather than thousands of SwiftUI gesture views. Above 200 tiles, a tile-number selector provides an accessible alternative to selecting a tiny tile on the canvas.

## Shape and text art

Choose Shape Collage or Text Collage at the top of the workspace, select the shape/text and tile count, then Generate. Choose Source Photos first, or enable Use entire photo library. Shape/text compositions can repeat sources to reach the requested count. Circle, diamond, heart, star and hexagon silhouettes are supported, plus rectangle and CoreText outline text (up to 64 characters). Text is fitted as a single line; spaces and letter counters remain empty. Outline availability depends on the font. Colour emoji and arbitrary bitmap masks are not supported.

A 512×512 integral occupancy map and mass-balanced rectangular partitions produce exactly the requested number of non-empty photo regions across a silhouette, including disconnected letters. Cells may have different sizes: this is a partitioned art collage rather than uniformly sized square tiles. Very thin/long text may not have enough sampled occupied pixels for the requested count; choose fewer tiles or shorter text in that case. Shape geometry and clipping are shared Core Graphics paths in top-left normalised coordinates. Preview and final rendering use those same paths.

Photo frame shape is separate: change the selected cell’s Photo frame shape, or Photo frame shape · all tiles under Shape, Text & Photo Mosaic. Individual rectangular, circular, diamond, heart, star and hexagonal frames work inside ordinary or silhouette compositions. Existing cell crops remain editable. Borders follow the shaped outline. Overall background can be white, black or transparent; transparency is retained by PNG export.

## Reference-image photomosaics

Import a reference into Photo Library, choose Photo Mosaic → Choose Reference Image, set candidate sources and tile count, then Generate. The reference is excluded from tile candidates. It fills/crops to the configured canvas aspect ratio. Matching evaluates actual processed source thumbnails, including applicable edits, and compares average colour plus 2×2 local colour/tone patterns. A colour kd-tree narrows candidates; a reuse penalty encourages variety among comparably matching photos. Sources are not tinted, and no reference-image fragments are pasted into cells. With reuse disabled, every tile uses a distinct source; insufficient usable sources cause an error. Unreadable candidate sources are counted and reported. A missing/invalid reference fails generation.

This is approximate colour/tone matching, not semantic image reconstruction or a guarantee of likeness. A small or similar-coloured photo library cannot recreate every reference. Analysis is serial and downsampled, feature vectors are temporary, and the generator’s thumbnail cache is disabled. It uses no third-party models, networking or uploads. Analysis/matching show progress, can be cancelled, and only replace the composition after successful completion. If the composition, source references or photo edits change while generation runs, the result is not applied. Completed cell placements are saved; changing photos or reference edits later does not silently regenerate the mosaic.

## Rendering, export and safety

The shared engine accepts up to 10,000 cells. Existing image/canvas limits still apply: maximum 20,000 pixels per axis and 100 million output pixels. Thousands of tiny tiles need a sufficiently large canvas to remain detailed. Spacing is capped relative to each tile so it cannot erase very small cells. Final source rendering is bounded to each cell’s raster needs, performed sequentially with autorelease pools, and uses a 16 MiB per-render tile cache. Progress is reported during final tile composition; cancellation preserves the previous project and any already-published outputs. Preview is downsampled and may show less detail than export.

Export captures the active composition, sources and edits before rendering. It publishes one validated PNG through the existing collision-safe pipeline and creates a sharing session from that operation’s successful output only. Other tabs are not exported. All edits start from private source snapshots; originals are never modified. Masks/annotations retain their normalised cell-output placement, so review coverage after reframing or changing cell shapes. Existing Safe to Share review still precedes native sharing.

## Compatibility and validation limits

Schema 4 gains optional collages/openCollageIDs/activeCollageID fields and keeps the legacy active collage field. Old projects migrate their single composition without changing its geometry. Cell shapes, template IDs, silhouette text and reference source IDs are additive Codable fields. No source data is embedded or duplicated by creating another composition.

Automated coverage includes all 74 templates with 37 sources each; preservation of cell IDs/crops; exact shape/text counts; transparency/clipping; 1,000-tile shape and photomosaic renders; actual red/blue reference-region matching; no-reuse behaviour; original-byte preservation; cancellation; legacy decoding; independent tab histories; closed-composition recovery and saved-tab restoration. Native view captures use generated images. Physical-device memory/interaction tests, representative 10,000-tile benchmarks, detachable/reorderable collage tabs and arbitrary imported vector/image silhouettes remain future validation/features.


Validation results for this update: macOS and iOS Simulator builds succeeded; 98 Core tests, 157 iOS app-host tests and 21 Mac tests passed. The iOS count includes Core tests and should not be treated as an additional independent Core run. Mac native Undo/Redo routes to the active collage while Collages is focused. Generation/export progress and Cancel remain visible above the scrolling canvas.


## Contextual creation and layout application

The creation choices expose Photo Layout, Shape Collage, Text Collage and Photo Mosaic directly. Art choices open a setup sheet; the reference chooser is presented within that sheet. The gallery’s primary action applies the selected arrangement to the active composition without creating a document. An explicit Create New Collage option creates another tab. Applying a layout retains source placements’ supported edits through the existing template engine and is reversible using composition Undo. Neither action deletes sources or modifies original files.
