import Dispatch

/// A platform-neutral, high-resolution monotonic clock shared by hosts and
/// retained runtimes.
///
/// Calendar time can jump when the system clock changes, and a clock owned by
/// one windowing implementation prevents an otherwise neutral runtime from
/// being embedded by another host. Dispatch's uptime clock is monotonic on
/// every supported Swift platform and has nanosecond input precision.
public enum PlatformClock {
    /// Seconds since the platform's monotonic-clock origin.
    ///
    /// The origin is intentionally unspecified. Only differences between
    /// timestamps produced by this clock have meaning.
    @inlinable
    public static func now() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }
}
