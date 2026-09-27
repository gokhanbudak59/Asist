// G10 (04 §3.4.6): "DURATION önce (hatırlat | haber ver | uyar | söyle)" and "DURATION kala" → leadTimesMinutes.
import Foundation

enum LeadTimeExtractor {
    static let leadVerbs: [[String]] = [["haber", "ver"], ["uyar"], ["soyle"], ["bildir"], ["haber", "verir", "misin"]]

    static func extract(_ ctx: inout ParseContext) {
        var i = 0
        while i < ctx.count {
            guard ctx.usable(i), let duration = ctx.durationPhrase(at: i), duration.unitSuffix.isEmpty else {
                i += 1
                continue
            }
            let markerIndex = duration.end + 1
            let marker = ctx.usablePlain(markerIndex)
            guard marker == "once" || marker == "kala" || marker == "evvel" else {
                i += 1
                continue
            }
            var verbEnd = -1
            let verbIndex = markerIndex + 1
            if ctx.usable(verbIndex) && CueExtractor.isHatirlaVerb(ctx.tokens[verbIndex]) {
                verbEnd = verbIndex
                if Lexicon.questionParticles.contains(ctx.usablePlain(verbIndex + 1)) {
                    verbEnd = verbIndex + 1
                }
            } else {
                let e = ctx.matchAny(verbIndex, leadVerbs)
                if e >= 0 {
                    verbEnd = e
                }
            }
            // "2 gün önce" alone may mean "two days ago": a lead needs the verb, except with "kala".
            if marker != "kala" && verbEnd < 0 {
                i += 1
                continue
            }
            let minutes = duration.totalMinutes
            if minutes > 0 && !ctx.leads.contains(minutes) {
                ctx.leads.append(minutes)
            }
            ctx.consume(duration.start, markerIndex)
            if verbEnd >= 0 {
                ctx.consume(verbIndex, verbEnd)
                ctx.leadCue = true
                ctx.verbCue = true
            }
            i = max(markerIndex, verbEnd) + 1
        }
        ctx.leads.sort()
    }
}
