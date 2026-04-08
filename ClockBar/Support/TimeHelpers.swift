func minutesSinceMidnight(_ time: String) -> Int {
    let parts = time.split(separator: ":").compactMap { Int($0) }
    let h = parts.indices.contains(0) ? parts[0] : 0
    let m = parts.indices.contains(1) ? parts[1] : 0
    return h * 60 + m
}

func minutesBetween(_ from: String, _ to: String) -> Int {
    minutesSinceMidnight(to) - minutesSinceMidnight(from)
}
