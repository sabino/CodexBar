#if os(Linux)
@_silgen_name("malloc_trim")
private func mallocTrim(_ padding: Int) -> Int32
#endif

/// Returns temporary allocator arenas after expensive, explicitly bounded work.
///
/// Swift values still in use remain untouched. glibc only releases completely
/// unused heap pages, so this is a no-op when there is nothing safe to return.
enum PlatformMemory {
    static func releaseUnusedHeapPages() {
        #if os(Linux)
        _ = mallocTrim(0)
        #endif
    }
}
