import Foundation
import Testing
@testable import FanKit

@Suite("Fan curve interpolation")
struct CurveTests {
    let curve = FanCurve(points: [
        CurvePoint(temperature: 40, rpm: 1500),
        CurvePoint(temperature: 60, rpm: 2500),
        CurvePoint(temperature: 80, rpm: 5000),
    ])

    @Test("below the first point holds the first rpm")
    func belowFirst() {
        #expect(curve.rpm(at: 20) == 1500)
        #expect(curve.rpm(at: 40) == 1500)
    }

    @Test("above the last point holds the last rpm")
    func aboveLast() {
        #expect(curve.rpm(at: 95) == 5000)
        #expect(curve.rpm(at: 80) == 5000)
    }

    @Test("interpolates linearly between points")
    func between() {
        #expect(curve.rpm(at: 50) == 2000)
        #expect(curve.rpm(at: 70) == 3750)
    }

    @Test("a single point behaves as a constant")
    func singlePoint() {
        let flat = FanCurve(points: [CurvePoint(temperature: 50, rpm: 2200)])
        #expect(flat.rpm(at: 10) == 2200)
        #expect(flat.rpm(at: 90) == 2200)
    }

    @Test("an empty curve yields nil so callers fall back to auto")
    func empty() {
        #expect(FanCurve(points: []).rpm(at: 50) == nil)
    }

    @Test("points given out of order are normalised")
    func unsorted() {
        let messy = FanCurve(points: [
            CurvePoint(temperature: 80, rpm: 5000),
            CurvePoint(temperature: 40, rpm: 1500),
        ])
        #expect(messy.rpm(at: 60) == 3250)
    }

    @Test("round-trips through JSON")
    func codable() throws {
        let data = try JSONEncoder().encode(curve)
        #expect(try JSONDecoder().decode(FanCurve.self, from: data) == curve)
    }

    @Test("a new curve is two points: resting when cool, full speed when hot")
    func starter() {
        let curve = FanCurve.starter(maxRPM: 5776)
        #expect(curve.points == [CurvePoint(temperature: 40, rpm: 0), CurvePoint(temperature: 90, rpm: 5776)])
    }

    @Test("points stop at ten and do not go below two")
    func pointLimits() {
        var curve = FanCurve.starter(maxRPM: 5000)
        curve.removePoint(at: 0)
        #expect(curve.points.count == 2)
        for t in stride(from: 45.0, through: 85.0, by: 5) { curve.addPoint(CurvePoint(temperature: t, rpm: 1000)) }
        #expect(curve.points.count == FanCurve.maxPoints)
    }
}
