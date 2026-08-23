#if !CrossPlatformApp
@main
enum CodexBarCrossDisabled {
    static func main() {
        print("CodexBarCross requires the CrossPlatformApp SwiftPM trait.")
    }
}
#endif
