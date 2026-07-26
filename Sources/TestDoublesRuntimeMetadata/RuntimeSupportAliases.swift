import TestDoublesRuntimeSupport

// Keep the package-only construction-error vocabulary reachable through the
// metadata target while its ownership lives in the lower support target.
package typealias RuntimeConstructionError =
    TestDoublesRuntimeSupport.RuntimeConstructionError
package typealias RuntimeForwardingUnsupportedReason =
    TestDoublesRuntimeSupport.RuntimeForwardingUnsupportedReason
