# Incremental import

File and recursive folder import enumerates lazily and copies one source at a time to a validated local snapshot. The first completed source enters the gallery immediately. Further arrivals are published in batches of at most 64 using a 150 ms timer, and pending arrivals are flushed on completion, cancellation or session save. These are scheduling targets, not guarantees against blocked operating-system I/O.

The All Images view with no search returns the source array directly, without classification or rebuilding a dictionary. Lazy grids request downsampled previews as needed. Users can scroll and edit completed sources while acquisition continues; edits and selection remain intact. A progress area displays discovered/imported/skipped/failed counts and current-file bytes. With an active filter, Show arriving images returns to All Images explicitly. Vision indexing follows acquisition rather than competing with copying and editing.

Autosave checkpoints during import are scheduled every five seconds of ongoing activity instead of rescheduling on every arrival. Cancellation retains completed sources. A stalled NAS read may delay cancellation until the filesystem call returns. Snapshots require local disk space.

Validation covers editing the first image during an actual 50-image import and an ordered, unindexed gallery containing 50,000 synthetic source records. The latter tests collection state, not 50,000 real image decodes, NAS throughput, or physical-device memory/performance.
