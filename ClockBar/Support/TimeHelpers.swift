func minutesSinceMidnight(_ time: String) -> Int {
    ScheduledTime(string: time)?.totalMinutes ?? 0
}

func minutesBetween(_ from: String, _ to: String) -> Int {
    minutesSinceMidnight(to) - minutesSinceMidnight(from)
}
