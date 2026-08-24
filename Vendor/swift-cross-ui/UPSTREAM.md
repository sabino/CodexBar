# SwiftCrossUI source

This directory contains the renderer targets CodexBar uses from
[`moreSwift/swift-cross-ui`](https://github.com/moreSwift/swift-cross-ui), pinned
from commit `f8bdf05729ae1cd1b7f3ec4e57177a6965052146` (the revision previously resolved
for SwiftCrossUI 0.9.x).

The upstream MIT license is preserved in `LICENSE`. Generated code, examples,
tests, documentation assets, and backends CodexBar does not link are omitted.

CodexBar carries one behavioral patch in `State/Publisher.swift`: UI observations
are delivered in FIFO order to the renderer's main thread. The upstream
implementation may drop queued observations and insert an adaptive sleep intended
for Gtk3. CodexBar preserves every observation and waits only for the current native
UI-thread action to finish; it never sleeps or inserts an artificial interval.

The private compile-time `BaseStubsTest` conformance is explicitly main-actor
isolated so the pinned source remains valid under the Swift 6.3 compiler. This
does not affect a runtime renderer.

Pure window resizes reuse the existing root view and recompute only layout for
the new proposal. State, environment, and navigation updates still provide a new
view normally. This avoids rebuilding an unchanged settings hierarchy for every
i3 configure event.

Pure native window resizes also reuse content-derived size limits, avoiding a
redundant intrinsic-size walk for every configure event.

The GTK backend ignores repeated fixed-widget size and position writes. The
last committed geometry lives on each native widget, so destroyed-object address
reuse cannot produce stale cache hits. The renderer remains authoritative and
every update is committed, while GTK avoids relayout notifications for geometry
that did not change.

GTK intrinsic widget measurements are memoized only for the duration of one
synchronous native resize delivery, then discarded before returning to GTK.

GTK text updates compare content, alignment, selection, and the complete CSS
block before touching the native label. A layout measurement no longer reloads
identical CSS or invalidates unchanged Pango text.

The GTK backend does not run the upstream 50 ms Foundation RunLoop tickler. It
installs Swift 6.3's typed custom `MainExecutor`, schedules each actor job as a
GLib idle source, and executes it on GTK's owning thread. Native callbacks and
observations therefore wake the GTK loop directly, with no polling cadence,
dropped jobs, artificial delay, or idle CPU wake-up.
