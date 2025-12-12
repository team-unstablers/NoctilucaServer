import Foundation
import SiriusKit

extension FrameDataHeader {
    init(frameID: UInt64, length: UInt32, presentationTimestamp: UInt64, isKeyFrame: Bool) {
        self.frameID = frameID
        self.frameLength = length
        self.presentationTimestamp = presentationTimestamp
        self.isKeyFrame = isKeyFrame
    }
}
