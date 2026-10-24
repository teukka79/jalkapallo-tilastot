import Foundation

extension SampleData {
    /// Esimerkkipelaajan laukaukset: määrät täsmäävät pelaajan lukuihin (yhteensä, maalia kohti, ulkopuolelta, maalit).
    static func shots(for player: Player) -> [Shot] {
        let seed = player.id.unicodeScalars.reduce(UInt64(29)) { $0 &* 31 &+ UInt64($1.value) }
        var rng = SeededRNG(seed: seed)

        let total = max(0, player.shots)
        let outside = min(max(0, player.shotsOutsideBox), total)
        let inside = total - outside
        let outsideOn = min(player.shotsOnTargetOutsideBox, outside)
        let insideOn = min(inside, max(0, player.shotsOnTarget - outsideOn))
        var goalsInside = min(player.goals, insideOn)
        var goalsOutside = min(player.goals - goalsInside, outsideOn)

        func make(isInside: Bool, onTarget: Bool, goal: Bool, rng: inout SeededRNG) -> Shot {
            let x: Double
            let y: Double
            if isInside {
                let u = Double.random(in: 0...1, using: &rng)
                x = 0.995 - pow(u, 1.6) * 0.15
                y = 0.5 + (Double.random(in: -1...1, using: &rng) + Double.random(in: -1...1, using: &rng)) / 2 * 0.28
            } else {
                x = Double.random(in: 0.66...0.84, using: &rng)
                y = 0.5 + (Double.random(in: -1...1, using: &rng) + Double.random(in: -1...1, using: &rng)) / 2 * 0.38
            }
            let result: ShotResult
            if goal {
                result = .goal
            } else if onTarget {
                result = .saved
            } else {
                let r = Int.random(in: 0..<10, using: &rng)
                result = r < 6 ? .missed : (r < 9 ? .blocked : .post)
            }
            let xg: Double
            if isInside {
                xg = goal ? Double.random(in: 0.15...0.6, using: &rng) : Double.random(in: 0.04...0.35, using: &rng)
            } else {
                xg = Double.random(in: 0.015...0.07, using: &rng)
            }
            let minute = Int.random(in: 1...94, using: &rng)
            return Shot(x: x, y: y, xG: (xg * 100).rounded() / 100, minute: minute, result: result)
        }

        var list: [Shot] = []
        for i in 0..<inside {
            let on = i < insideOn
            var goal = false
            if on && goalsInside > 0 { goal = true; goalsInside -= 1 }
            list.append(make(isInside: true, onTarget: on, goal: goal, rng: &rng))
        }
        for i in 0..<outside {
            let on = i < outsideOn
            var goal = false
            if on && goalsOutside > 0 { goal = true; goalsOutside -= 1 }
            list.append(make(isInside: false, onTarget: on, goal: goal, rng: &rng))
        }
        return list
    }

    /// Esimerkkiottelun maalit: tekijät valitaan joukkueen esimerkkipelaajista.
    static func goals(for match: Match) -> [GoalEvent] {
        guard match.status == .finished, let homeGoals = match.homeGoals, let awayGoals = match.awayGoals else { return [] }
        let league = League(rawValue: match.league) ?? .premierLeague
        let pool = players(for: league)
        let seed = match.id.unicodeScalars.reduce(UInt64(41)) { $0 &* 31 &+ UInt64($1.value) }
        var rng = SeededRNG(seed: seed)

        func events(team: String, count: Int, isHome: Bool, rng: inout SeededRNG) -> [GoalEvent] {
            let squad = pool.filter { $0.team == team }
            guard !squad.isEmpty, count > 0 else { return [] }
            let weights = squad.map { Double($0.goals + 1 + ($0.position == .forward ? 3 : 0)) }
            let sum = weights.reduce(0, +)
            var result: [GoalEvent] = []
            for _ in 0..<count {
                var roll = Double.random(in: 0..<sum, using: &rng)
                var scorer = squad[0]
                for (index, weight) in weights.enumerated() {
                    if roll < weight { scorer = squad[index]; break }
                    roll -= weight
                }
                let assister = Double.random(in: 0...1, using: &rng) < 0.6
                    ? squad.filter { $0.id != scorer.id }.randomElement(using: &rng)?.name : nil
                result.append(GoalEvent(minute: Int.random(in: 1...90, using: &rng), extra: nil, isHome: isHome,
                                        scorer: scorer.name, assist: assister, kind: nil))
            }
            return result
        }

        let all = events(team: match.home, count: homeGoals, isHome: true, rng: &rng)
            + events(team: match.away, count: awayGoals, isHome: false, rng: &rng)
        return all.sorted { $0.minute < $1.minute }
    }
}
