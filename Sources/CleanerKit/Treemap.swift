import CoreGraphics

/// Squarified treemap layout (Bruls, Huizing, van Wijk 2000).
public enum Treemap {
    /// Rectangles for `values`, in the same order. Pass values sorted largest first for the best aspect ratios.
    /// Zero or negative values get `.zero`.
    public static func layout(_ values: [Double], in bounds: CGRect) -> [CGRect] {
        var result = Array(repeating: CGRect.zero, count: values.count)
        let total = values.reduce(0) { $0 + max($1, 0) }
        guard total > 0, bounds.width > 0, bounds.height > 0 else { return result }

        let scale = Double(bounds.width * bounds.height) / total
        let items = values.indices.filter { values[$0] > 0 }.map { (index: $0, area: values[$0] * scale) }
        var remaining = bounds
        var start = 0

        while start < items.count {
            let side = Double(min(remaining.width, remaining.height))
            var end = start + 1
            while end < items.count,
                  worst(items[start...end].map(\.area), side: side) <= worst(items[start..<end].map(\.area), side: side) {
                end += 1
            }
            let row = items[start..<end]
            let rowArea = row.reduce(0) { $0 + $1.area }
            if remaining.width >= remaining.height {
                let width = CGFloat(rowArea / Double(remaining.height))
                var y = remaining.minY
                for item in row {
                    let height = CGFloat(item.area) / width
                    result[item.index] = CGRect(x: remaining.minX, y: y, width: width, height: height)
                    y += height
                }
                remaining = CGRect(x: remaining.minX + width, y: remaining.minY,
                                   width: max(remaining.width - width, 0), height: remaining.height)
            } else {
                let height = CGFloat(rowArea / Double(remaining.width))
                var x = remaining.minX
                for item in row {
                    let width = CGFloat(item.area) / height
                    result[item.index] = CGRect(x: x, y: remaining.minY, width: width, height: height)
                    x += width
                }
                remaining = CGRect(x: remaining.minX, y: remaining.minY + height,
                                   width: remaining.width, height: max(remaining.height - height, 0))
            }
            start = end
        }
        return result
    }

    /// Worst aspect ratio of a row laid along a side of length `side`.
    static func worst(_ areas: [Double], side: Double) -> Double {
        let sum = areas.reduce(0, +)
        guard let maxArea = areas.max(), let minArea = areas.min(), sum > 0, minArea > 0 else { return .infinity }
        let s2 = sum * sum, w2 = side * side
        return max(w2 * maxArea / s2, s2 / (w2 * minArea))
    }
}
