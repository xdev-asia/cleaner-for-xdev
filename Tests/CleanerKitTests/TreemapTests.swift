import CoreGraphics
import Testing
@testable import CleanerKit

@Suite struct TreemapTests {
    let bounds = CGRect(x: 10, y: 20, width: 600, height: 400)

    @Test func areasAreProportionalAndFillTheRect() {
        let values: [Double] = [500, 250, 120, 80, 30, 15, 5]
        let rects = Treemap.layout(values, in: bounds)
        #expect(rects.count == values.count)
        let total = values.reduce(0, +)
        for (value, rect) in zip(values, rects) {
            let expected = Double(bounds.width * bounds.height) * value / total
            #expect(abs(Double(rect.width * rect.height) - expected) < 1)
        }
    }

    @Test func rectsStayInsideAndDoNotOverlap() {
        let rects = Treemap.layout([9, 8, 7, 6, 5, 4, 3, 2, 1], in: bounds)
        for rect in rects {
            #expect(bounds.insetBy(dx: -0.001, dy: -0.001).contains(rect))
        }
        for i in rects.indices {
            for j in rects.indices where j > i {
                let overlap = rects[i].intersection(rects[j])
                #expect(overlap.isNull || overlap.width * overlap.height < 0.01)
            }
        }
    }

    @Test func equalValuesGiveNearSquares() {
        let rects = Treemap.layout(Array(repeating: 1, count: 16), in: CGRect(x: 0, y: 0, width: 400, height: 400))
        for rect in rects {
            #expect(max(rect.width / rect.height, rect.height / rect.width) < 1.5)
        }
    }

    @Test func zeroAndEmptyInputs() {
        #expect(Treemap.layout([], in: bounds).isEmpty)
        let rects = Treemap.layout([10, 0], in: bounds)
        #expect(rects[1] == .zero)
        #expect(abs(rects[0].width * rects[0].height - bounds.width * bounds.height) < 1)
    }
}
