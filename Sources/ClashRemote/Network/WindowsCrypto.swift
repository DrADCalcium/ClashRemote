#if os(Windows)
import Foundation
import CWindowsPlatform

typealias CC_LONG = UInt32
typealias CCHmacAlgorithm = UInt32
let CC_MD5_DIGEST_LENGTH = 16
let CC_SHA256_DIGEST_LENGTH = 32
let kCCHmacAlgMD5: UInt32 = 1

@discardableResult
func CC_MD5(_ input: UnsafeRawPointer?, _ length: CC_LONG, _ output: UnsafeMutablePointer<UInt8>) -> UnsafeMutablePointer<UInt8>? {
    precondition(cr_digest(input?.assumingMemoryBound(to: UInt8.self), Int(length), nil, 0, 1, output, 16) == 1, "Windows CNG MD5 failure")
    return output
}
@discardableResult
func CC_SHA256(_ input: UnsafeRawPointer?, _ length: CC_LONG, _ output: UnsafeMutablePointer<UInt8>) -> UnsafeMutablePointer<UInt8>? {
    precondition(cr_digest(input?.assumingMemoryBound(to: UInt8.self), Int(length), nil, 0, 2, output, 32) == 1, "Windows CNG SHA256 failure")
    return output
}
func CCHmac(_ algorithm: CCHmacAlgorithm, _ key: UnsafeRawPointer?, _ keyLength: Int, _ input: UnsafeRawPointer?, _ length: Int, _ output: UnsafeMutableRawPointer) {
    precondition(algorithm == kCCHmacAlgMD5)
    precondition(cr_digest(input?.assumingMemoryBound(to: UInt8.self), length, key?.assumingMemoryBound(to: UInt8.self), keyLength, 3, output.assumingMemoryBound(to: UInt8.self), 16) == 1, "Windows CNG HMAC failure")
}
#endif
