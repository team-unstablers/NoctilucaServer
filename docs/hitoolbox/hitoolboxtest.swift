import ApplicationServices
import Carbon


let inputSources: [TISInputSource] = TISCreateInputSourceList(nil, false)!
    .takeRetainedValue() as! [TISInputSource]

for inputSource in inputSources {
    guard let langsPtr = TISGetInputSourceProperty(
        inputSource, kTISPropertyInputSourceLanguages
    ) else { continue }


    guard let enabledPtr = TISGetInputSourceProperty(
        inputSource, kTISPropertyInputSourceIsEnabled
    ) else { continue }

    // CFArray<CFString> → [String] toll-free bridging
    let languages = Unmanaged<CFArray>
        .fromOpaque(langsPtr)
        .takeUnretainedValue() as! [String]

    let sourceID: String = {
        guard let ptr = TISGetInputSourceProperty(
            inputSource, kTISPropertyInputSourceID
        ) else { return "?" }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }()

    print("\(sourceID): \(languages)")
}
