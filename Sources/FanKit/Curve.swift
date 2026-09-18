import Foundation

/// One handle on a fan curve: at `temperature` the fan should run at `rpm`.
public struct CurvePoint: Codable, Equatable, Sendable, Identifiable {
    public var temperature: Double
    public var rpm: Double
    public var id: String { "\(temperature)-\(rpm)" }

    public init(temperature: Double, rpm: Double) {
        self.temperature = temperature
        self.rpm = rpm
    }
}

/// A piecewise-linear temperature-to-rpm mapping. Flat beyond its end points.
public struct FanCurve: Codable, Equatable, Sendable {
    /// Always kept sorted by temperature.
    public private(set) var points: [CurvePoint]

    public init(points: [CurvePoint]) {
        self.points = points.sorted { $0.temperature < $1.temperature }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(points: try container.decode([CurvePoint].self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(points)
    }

    /// The demanded rpm at `temperature`, or nil when the curve has no points.
    public func rpm(at temperature: Double) -> Double? {
        guard let first = points.first, let last = points.last else { return nil }
        if temperature <= first.temperature { return first.rpm }
        if temperature >= last.temperature { return last.rpm }
        for (a, b) in zip(points, points.dropFirst()) where temperature <= b.temperature {
            let span = b.temperature - a.temperature
            guard span > 0 else { return b.rpm }
            let ratio = (temperature - a.temperature) / span
            return a.rpm + (b.rpm - a.rpm) * ratio
        }
        return last.rpm
    }

    // MARK: Editing

    /// A curve is a line, so it needs two points; past ten it is fiddling, not shaping.
    public static let minPoints = 2
    public static let maxPoints = 10

    public mutating func movePoint(at index: Int, to point: CurvePoint) {
        guard points.indices.contains(index) else { return }
        points[index] = point
        points.sort { $0.temperature < $1.temperature }
    }

    public mutating func addPoint(_ point: CurvePoint) {
        guard points.count < Self.maxPoints else { return }
        points.append(point)
        points.sort { $0.temperature < $1.temperature }
    }

    public mutating func removePoint(at index: Int) {
        guard points.indices.contains(index), points.count > Self.minPoints else { return }
        points.remove(at: index)
    }

    /// What a new curve starts as: at rest while cool - the hardware stops at zero, as
    /// the system's own controller stops it - and flat out when hot. Two points, so it
    /// is shaped by adding what it needs rather than by clearing out what it does not.
    public static func starter(maxRPM: Double) -> FanCurve {
        FanCurve(points: [
            CurvePoint(temperature: 40, rpm: 0),
            CurvePoint(temperature: 90, rpm: maxRPM),
        ])
    }
}
