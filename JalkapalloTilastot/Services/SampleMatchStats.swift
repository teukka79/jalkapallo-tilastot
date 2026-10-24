import Foundation

/// Generoi uskottavat ottelutilastot esimerkkidatan päättyneille otteluille.
/// Luvut ovat sidoksissa lopputulokseen (laukaukset ≥ maalit, sisä + ulko = yhteensä) ja puoliajat summautuvat kokonaisuudeksi.
private func statCount(_ n: Int) -> StatValue { StatValue(value: Double(n)) }
private func statRound2(_ v: Double) -> Double { (v * 100).rounded() / 100 }

private struct StatSynth {
    var rng: SeededRNG

    mutating func int(_ range: ClosedRange<Int>) -> Int { Int.random(in: range, using: &rng) }
    mutating func dbl(_ range: ClosedRange<Double>) -> Double { Double.random(in: range, using: &rng) }
    mutating func chance(oneIn n: Int) -> Bool { int(1...n) == 1 }

    private mutating func ratio(attempts: ClosedRange<Int>, rate: ClosedRange<Double>) -> StatValue {
        let n = int(attempts)
        let made = Int((Double(n) * dbl(rate)).rounded())
        return StatValue(value: Double(made), attempts: Double(n))
    }

    private mutating func side(goals: Int, conceded: Int, strength s: Double, opp: Double,
                               possession p: Double) -> [StatKey: StatValue] {
        let press = 0.6 + 0.8 * s - 0.3 * opp + (p - 50) / 100
        let strong = press > 0.9

        let onTarget = goals + int(0...(strong ? 2 : 1))
        let off = int(0...(strong ? 3 : 2))
        let blocked = int(0...2)
        let total = onTarget + off + blocked
        let insideRaw = Int((Double(total) * dbl(0.42...0.7)).rounded())
        let inside = min(total, max(goals, insideRaw))
        let outside = total - inside
        let big = min(inside, int(0...1) + (goals > 1 ? 1 : 0))

        let xG = statRound2(Double(inside) * dbl(0.07...0.14) + Double(outside) * dbl(0.02...0.05) + Double(big) * 0.28)
        let xGOT = statRound2(Double(onTarget) * dbl(0.09...0.16))
        let xA = statRound2(xG * dbl(0.5...0.95))

        let passAttempts = max(40, Int(p * 1.9) + int(-12...12))
        let passMade = Int((Double(passAttempts) * dbl(0.74...0.9)).rounded())

        var v: [StatKey: StatValue] = [:]
        v[.xG] = StatValue(value: xG)
        v[.xGOT] = StatValue(value: xGOT)
        v[.xA] = StatValue(value: xA)
        v[.shots] = statCount(total)
        v[.shotsOnTarget] = statCount(onTarget)
        v[.shotsOffTarget] = statCount(off)
        v[.blockedShots] = statCount(blocked)
        v[.shotsInsideBox] = statCount(inside)
        v[.shotsOutsideBox] = statCount(outside)
        v[.hitWoodwork] = statCount(chance(oneIn: 10) ? 1 : 0)
        v[.bigChances] = statCount(big)
        v[.corners] = statCount(int(0...3) + (strong ? 1 : 0))
        v[.touchesInBox] = statCount(inside * 2 + int(2...6))
        v[.throughPasses] = statCount(chance(oneIn: 6) ? 1 : 0)
        v[.offsides] = statCount(int(0...1))
        v[.freeKicks] = statCount(int(2...6))
        v[.passes] = StatValue(value: Double(passMade), attempts: Double(passAttempts))
        v[.longBalls] = ratio(attempts: 4...12, rate: 0.4...0.6)
        v[.finalThirdPasses] = ratio(attempts: 12...30, rate: 0.58...0.75)
        v[.crosses] = ratio(attempts: 1...6, rate: 0.15...0.4)
        v[.throwIns] = statCount(int(3...8))
        v[.fouls] = statCount(int(3...8))
        v[.tackles] = ratio(attempts: 1...5, rate: 0.5...0.85)
        v[.duelsWon] = statCount(int(8...16))
        v[.clearances] = statCount(int(2...9) + (press < 0.8 ? 3 : 0))
        v[.interceptions] = statCount(int(0...4))
        v[.errorsToShot] = statCount(chance(oneIn: 4) ? 1 : 0)
        v[.errorsToGoal] = statCount(conceded > 0 && chance(oneIn: 4) ? 1 : 0)
        v[.yellowCards] = statCount(int(0...1) + (chance(oneIn: 5) ? 1 : 0))
        v[.redCards] = statCount(chance(oneIn: 40) ? 1 : 0)
        return v
    }

    mutating func half(goalsHome: Int, goalsAway: Int, strengthHome sH: Double, strengthAway sA: Double) -> [StatKey: StatPair] {
        let homePossession = min(65, max(35, 50 + (sH - sA) * 14 + dbl(-5...5))).rounded()
        let home = side(goals: goalsHome, conceded: goalsAway, strength: sH, opp: sA, possession: homePossession)
        let away = side(goals: goalsAway, conceded: goalsHome, strength: sA, opp: sH, possession: 100 - homePossession)

        var out: [StatKey: StatPair] = [:]
        for (key, h) in home {
            if let a = away[key] { out[key] = StatPair(home: h, away: a) }
        }
        out[.possession] = StatPair(home: StatValue(value: homePossession),
                                    away: StatValue(value: 100 - homePossession))
        let homeOn = home[.shotsOnTarget]?.value ?? 0
        let awayOn = away[.shotsOnTarget]?.value ?? 0
        out[.saves] = StatPair(home: StatValue(value: max(0, awayOn - Double(goalsAway))),
                               away: StatValue(value: max(0, homeOn - Double(goalsHome))))
        return out
    }
}

extension SampleData {
    /// Päättyneen esimerkkiottelun tilastot; sama ottelu tuottaa aina samat luvut.
    static func stats(for match: Match) -> MatchStats? {
        guard match.status == .finished, let homeGoals = match.homeGoals, let awayGoals = match.awayGoals else { return nil }
        let league = League(rawValue: match.league) ?? .premierLeague
        let names = teams[league] ?? []
        let sH = strength(of: match.home, in: names)
        let sA = strength(of: match.away, in: names)

        let seed = match.id.unicodeScalars.reduce(UInt64(13)) { $0 &* 31 &+ UInt64($1.value) }
        var synth = StatSynth(rng: SeededRNG(seed: seed))

        var homeFirst = 0, awayFirst = 0
        for _ in 0..<homeGoals { if synth.chance(oneIn: 2) { homeFirst += 1 } }
        for _ in 0..<awayGoals { if synth.chance(oneIn: 2) { awayFirst += 1 } }

        let first = synth.half(goalsHome: homeFirst, goalsAway: awayFirst, strengthHome: sH, strengthAway: sA)
        let second = synth.half(goalsHome: homeGoals - homeFirst, goalsAway: awayGoals - awayFirst,
                                strengthHome: sH, strengthAway: sA)
        return MatchStats(periods: [.full: MatchStats.combine(first, second),
                                    .firstHalf: first,
                                    .secondHalf: second],
                          isSample: true)
    }
}
