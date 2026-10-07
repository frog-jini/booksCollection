/// 읽기 속도(WPM)와, 속도에 맞춘 페이지 넘김 대기 시간.
public final class ReadingSpeed {
    public let window: Double
    public let defaultWPM: Double
    private var samples: [(t: Double, progress: Int)] = []
    private var maxIndex: Int?
    private var progress = 0

    public init(window: Double = 60, defaultWPM: Double = 200) {
        self.window = window
        self.defaultWPM = defaultWPM
    }

    public func update(wordIndex: Int, t: Double) {
        if let m = maxIndex {
            if wordIndex > m {  // 되돌아 읽기는 전진으로 치지 않는다
                progress += wordIndex - m
                maxIndex = wordIndex
            }
        } else {
            maxIndex = wordIndex
        }
        samples.append((t, progress))
        while samples.count > 1 && samples[0].t < t - window { samples.removeFirst() }
    }

    public var wpm: Double {
        guard samples.count >= 2, let a = samples.first, let b = samples.last, b.t > a.t else { return 0 }
        return Double(b.progress - a.progress) / (b.t - a.t) * 60
    }

    public func secondsFor(words: Int) -> Double {
        Double(words) / (wpm > 0 ? wpm : defaultWPM) * 60
    }

    /// 마지막 단어를 이만큼 보면 페이지를 넘긴다: 단어 몇 개를 읽는 시간.
    public func turnDwell(words: Int = 3, low: Double = 0.6, high: Double = 2.0) -> Double {
        min(high, max(low, secondsFor(words: words)))
    }
}
