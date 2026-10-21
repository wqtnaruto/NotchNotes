import Foundation

/// 合并并索引有序文本区间，让高频包含判断保持 O(log n)。
struct MarkdownRangeIndex {
    private let ranges: [NSRange]

    init(ranges: [NSRange]) {
        let sorted = ranges
            .filter { $0.location != NSNotFound && $0.length > 0 }
            .sorted { $0.location < $1.location }
        var merged: [NSRange] = []
        merged.reserveCapacity(sorted.count)
        for range in sorted {
            guard let last = merged.last else {
                merged.append(range)
                continue
            }
            if range.location <= NSMaxRange(last) {
                merged[merged.count - 1].length = max(NSMaxRange(last), NSMaxRange(range)) - last.location
            } else {
                merged.append(range)
            }
        }
        self.ranges = merged
    }

    func intersects(_ range: NSRange) -> Bool {
        guard range.location != NSNotFound, range.length > 0, !ranges.isEmpty else { return false }
        let end = NSMaxRange(range)
        var low = 0
        var high = ranges.count
        while low < high {
            let mid = (low + high) / 2
            if NSMaxRange(ranges[mid]) <= range.location {
                low = mid + 1
            } else {
                high = mid
            }
        }
        guard low < ranges.count else { return false }
        return ranges[low].location < end
    }
}
