import Foundation
import Carbon

import Gesu

typealias CGSConnectionID = Int

@PrivateLibrary(path: "/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/HIToolbox")
class HIToolboxPrivate {
    #PrivateFunction(
        "TSMSelectInputSource",
        args: (TISInputSource.self),
        ret: UInt.self
    )
}

func main() {
    try! HIToolboxPrivate.open()
    
    let current = TISCopyCurrentKeyboardInputSource()
    
    let x = TISCreateInputSourceList([
        kTISPropertyInputModeID: "com.apple.inputmethod.Korean.2SetKorean" as CFString
    ] as CFDictionary, false)
    guard let methods = x?.takeRetainedValue() as? [TISInputSource],
          var ko2Bulsik = methods.first else {
        return
    }
    
    let result = HIToolboxPrivate.TSMSelectInputSource?(ko2Bulsik)
    print(result)
}

main()
