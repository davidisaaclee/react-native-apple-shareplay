import Foundation

@objc public class SwiftFile: NSObject {
    @objc public func multiplyByThree(_ x: NSNumber) -> NSNumber {
        return NSNumber(value: x.intValue * 3)
    }
}
