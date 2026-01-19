import Foundation
import CoreGraphics

import Gesu

typealias CGSConnectionID = Int

@PrivateLibrary(path: "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
class CGPrivateLibrary {
    #PrivateFunction(
        "CGSMainConnectionID",
        args: (),
        ret: CGSConnectionID.self
    )
    
    #PrivateFunction(
        "CGSGetGlobalCursorDataSize",
        args: (CGSConnectionID.self, UnsafeMutablePointer<size_t>.self),
        ret: CGError.self
    )
}

func main() {
    try! CGPrivateLibrary.open()
    
    guard let CGSMainConnectionID = CGPrivateLibrary.CGSMainConnectionID else {
        fatalError("CGSMainConnectionID() not available")
    }
    
    let connectionID = CGSMainConnectionID()
    print("connection id = \(connectionID)")
    
    guard let CGSGetGlobalCursorDataSize = CGPrivateLibrary.CGSGetGlobalCursorDataSize else {
        fatalError("CGSGetGlobalCursorDataSize() not available")
    }
    
    var cursorSize: size_t = 0
    let error = CGSGetGlobalCursorDataSize(connectionID, &cursorSize)
    
    guard error == .success else {
        fatalError("CGSGetGlobalCursorDataSize() failed: \(error)")
    }
    
    print("cursor size = \(cursorSize)")
}

main()
