import Foundation

#if canImport(CoreFoundation)
import CoreFoundation
#endif

/// Keeps JSON `Bool` values distinct from numeric `NSNumber` values on every Swift platform.
///
/// Darwin and swift-corelibs-foundation expose CoreFoundation's canonical boolean type ID.
/// The Windows Foundation runtime does not ship a CoreFoundation module, but preserves the
/// Objective-C type encoding used by JSONSerialization (`c` for booleans).
enum FoundationNumberBridge {
    static func isBoolean(_ number: NSNumber) -> Bool {
        #if canImport(CoreFoundation)
        CFGetTypeID(number) == CFBooleanGetTypeID()
        #else
        String(cString: number.objCType) == "c"
        #endif
    }
}
