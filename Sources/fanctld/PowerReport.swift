import Foundation
import FanKit

/// What each of the Mac's engines has spent since the last reading.
///
/// IOReport is the interface `powermetrics` is built on. It is private - there is no
/// header for it - so it is reached by name through `libIOReport.dylib`, and every
/// symbol is optional: a macOS that moves or drops one leaves the daemon without
/// engine power and with every sensor still named from its key layout, rather than
/// without a daemon.
///
/// No privileges are needed, which is what makes this usable at all: the app cannot
/// ask for power, but the daemon reads it on the same tick as the sensors, and the
/// pair is what `EngineAffinity` learns from.
final class PowerReport {
    private typealias Subscription = OpaquePointer

    private let copyChannels: @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFMutableDictionary>?
    private let createSubscription: @convention(c) (UnsafeRawPointer?, CFMutableDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?, UInt64, CFTypeRef?) -> Subscription?
    private let createSamples: @convention(c) (Subscription, CFMutableDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private let samplesDelta: @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private let iterate: @convention(c) (CFDictionary, @convention(block) (CFDictionary) -> Int32) -> Void
    private let channelName: @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private let integerValue: @convention(c) (CFDictionary, Int32) -> Int64

    private let subscription: Subscription
    private let subscribed: CFMutableDictionary
    private var previous: CFDictionary?

    init?() {
        guard let library = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY) else { return nil }
        func symbol<T>(_ name: String, as: T.Type = T.self) -> T? {
            guard let pointer = dlsym(library, name) else { return nil }
            return unsafeBitCast(pointer, to: T.self)
        }
        guard let copyChannels: @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFMutableDictionary>? =
                symbol("IOReportCopyChannelsInGroup"),
              let createSubscription: @convention(c) (UnsafeRawPointer?, CFMutableDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?, UInt64, CFTypeRef?) -> Subscription? =
                symbol("IOReportCreateSubscription"),
              let createSamples: @convention(c) (Subscription, CFMutableDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>? =
                symbol("IOReportCreateSamples"),
              let samplesDelta: @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>? =
                symbol("IOReportCreateSamplesDelta"),
              let iterate: @convention(c) (CFDictionary, @convention(block) (CFDictionary) -> Int32) -> Void =
                symbol("IOReportIterate"),
              let channelName: @convention(c) (CFDictionary) -> Unmanaged<CFString>? =
                symbol("IOReportChannelGetChannelName"),
              let integerValue: @convention(c) (CFDictionary, Int32) -> Int64 =
                symbol("IOReportSimpleGetIntegerValue")
        else { return nil }

        guard let desired = copyChannels("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue()
        else { return nil }
        var subscribedOut: Unmanaged<CFMutableDictionary>?
        guard let subscription = createSubscription(nil, desired, &subscribedOut, 0, nil),
              let subscribed = subscribedOut?.takeRetainedValue()
        else { return nil }

        self.copyChannels = copyChannels
        self.createSubscription = createSubscription
        self.createSamples = createSamples
        self.samplesDelta = samplesDelta
        self.iterate = iterate
        self.channelName = channelName
        self.integerValue = integerValue
        self.subscription = subscription
        self.subscribed = subscribed
        self.previous = createSamples(subscription, subscribed, nil)?.takeRetainedValue()
        guard previous != nil else { return nil }
    }

    /// Energy spent per engine since the previous call, in whatever unit IOReport
    /// counts in - which does not matter, because the learner standardises.
    func sinceLastReading() -> [Engine: Double] {
        guard let previous, let now = createSamples(subscription, subscribed, nil)?.takeRetainedValue(),
              let delta = samplesDelta(previous, now, nil)?.takeRetainedValue()
        else { return [:] }
        self.previous = now

        var totals: [Engine: Double] = [:]
        iterate(delta) { [channelName, integerValue] channel in
            guard let name = channelName(channel)?.takeUnretainedValue() as String? else { return 0 }
            if let engine = Engine.forPowerChannel(name) {
                totals[engine, default: 0] += Double(integerValue(channel, 0))
            }
            return 0   // kIOReportIterOk
        }
        return totals
    }
}
