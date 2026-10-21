'use strict';
/* Generoitu esimerkkidata, jotta appi toimii ilman API-avainta.
   Pelaajien nimet ja luvut ovat keksittyjä eivätkä kuvaa oikeita henkilöitä. */
(function () {
  const TEAMS = {
    PL: ['Arsenal', 'Man City', 'Liverpool', 'Chelsea', 'Tottenham', 'Man United', 'Newcastle', 'Aston Villa', 'Brighton', 'West Ham', 'Crystal Palace', 'Fulham', 'Brentford', 'Everton', 'Wolves', 'Bournemouth', 'Nottingham Forest', 'Leeds', 'Sunderland', 'Burnley'],
    PD: ['Real Madrid', 'Barcelona', 'Atlético Madrid', 'Athletic Club', 'Real Sociedad', 'Villarreal', 'Betis', 'Sevilla', 'Valencia', 'Girona', 'Celta Vigo', 'Osasuna', 'Getafe', 'Mallorca', 'Rayo Vallecano', 'Espanyol', 'Alavés', 'Levante', 'Elche', 'Real Oviedo'],
    SA: ['Inter', 'Milan', 'Juventus', 'Napoli', 'Atalanta', 'Roma', 'Lazio', 'Fiorentina', 'Bologna', 'Torino', 'Genoa', 'Udinese', 'Como', 'Cagliari', 'Parma', 'Lecce', 'Sassuolo', 'Cremonese', 'Pisa', 'Verona'],
    FL1: ['PSG', 'Marseille', 'Monaco', 'Lyon', 'Lille', 'Nice', 'Lens', 'Rennes', 'Strasbourg', 'Brest', 'Toulouse', 'Nantes', 'Auxerre', 'Angers', 'Le Havre', 'Lorient', 'Metz', 'Paris FC'],
    BL1: ['Bayern München', 'Dortmund', 'Leverkusen', 'RB Leipzig', 'Eintracht Frankfurt', 'Stuttgart', 'Freiburg', 'Wolfsburg', 'Hoffenheim', 'Gladbach', 'Werder Bremen', 'Mainz', 'Augsburg', 'Union Berlin', 'St. Pauli', 'Heidenheim', 'Köln', 'Hamburger SV'],
    CL: ['Real Madrid', 'Bayern München', 'Man City', 'Arsenal', 'PSG', 'Inter', 'Barcelona', 'Liverpool', 'Dortmund', 'Atlético Madrid', 'Juventus', 'Leverkusen', 'Napoli', 'Benfica', 'Sporting CP', 'PSV']
  };
  const FIRST = ['Luca', 'Mateo', 'Jonas', 'Rafael', 'Diego', 'Marco', 'Lukas', 'Hugo', 'Pablo', 'Andre', 'Felix', 'Nico', 'Samuel', 'Tomas', 'Emil', 'Victor', 'Karim', 'Jules', 'Enzo', 'Bruno', 'Leon', 'Adrian', 'Milan', 'Oscar', 'Theo', 'Ivan', 'Rui', 'Sven'];
  const LAST = ['Moreau', 'Ferrer', 'Lindqvist', 'Costa', 'Brandt', 'Rossi', 'Navarro', 'Keller', 'Duarte', 'Novak', 'Haddad', 'Berg', 'Silva', 'Marchetti', 'Vidal', 'Okafor', 'Lambert', 'Ortega', 'Hartmann', 'Petrov', 'Santos', 'Bianchi', 'Dubois', 'Weber', 'Garcia', 'Moretti', 'Fontaine', 'Kovac', 'Aranda', 'Schulz', 'Pereira', 'Lund'];
  const FLAGS = ['🇫🇮', '🇸🇪', '🇧🇷', '🇦🇷', '🇫🇷', '🇩🇪', '🇪🇸', '🇮🇹', '🇵🇹', '🇳🇱', '🇳🇴', '🇩🇰', '🇭🇷', '🇳🇬', '🇲🇦', '🇧🇪', '🇨🇮', '🇺🇾'];
  const PLAYED = 8;

  function seedOf(code) {
    let h = 7;
    for (const ch of code) h = (Math.imul(h, 31) + ch.codePointAt(0)) >>> 0;
    return h;
  }

  function rng(seed) {
    let a = seed >>> 0;
    return function () {
      a = (a + 0x6D2B79F5) >>> 0;
      let t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  const randInt = (r, a, b) => a + Math.floor(r() * (b - a + 1));
  const randF = (r, a, b) => a + r() * (b - a);
  const pick = (r, arr) => arr[Math.floor(r() * arr.length)];

  function players(code) {
    const names = TEAMS[code] || [];
    const r = rng(seedOf(code) + 99);
    const layout = ['Hyökkääjä', 'Hyökkääjä', 'Hyökkääjä', 'Keskikenttä', 'Keskikenttä', 'Keskikenttä', 'Keskikenttä', 'Puolustaja', 'Puolustaja', 'Puolustaja'];
    const out = [];
    names.forEach((team, ti) => {
      const strength = 1 - (ti / names.length) * 0.7;
      layout.forEach((position, slot) => {
        const apps = randInt(r, PLAYED - 3, PLAYED);
        let perGame, outsideShare;
        if (position === 'Hyökkääjä') { perGame = 3.0; outsideShare = 0.28; }
        else if (position === 'Keskikenttä') { perGame = 1.7; outsideShare = 0.55; }
        else { perGame = 0.8; outsideShare = 0.5; }
        const volume = perGame * apps * (0.7 + 0.5 * strength);
        const shots = Math.round(volume * randF(r, 0.6, 1.4));
        const onTarget = Math.min(shots, Math.round(shots * randF(r, 0.28, 0.48)));
        const outside = Math.min(shots, Math.round(shots * outsideShare * randF(r, 0.7, 1.3)));
        const outsideOn = Math.min(outside, onTarget, Math.round(outside * randF(r, 0.2, 0.4)));
        const goals = Math.min(onTarget, Math.round(onTarget * randF(r, 0.2, 0.5)));
        out.push({
          id: `${code}-${ti}-${slot}`,
          name: `${pick(r, FIRST)} ${pick(r, LAST)}`,
          team, league: code, nationality: pick(r, FLAGS), position,
          appearances: apps, goals, shots, shotsOnTarget: onTarget,
          shotsOutsideBox: outside, shotsOnTargetOutsideBox: outsideOn
        });
      });
    });
    return out;
  }

  function roundRobin(names) {
    const arr = names.slice();
    const n = arr.length;
    const rounds = [];
    for (let r = 0; r < n - 1; r++) {
      const pairs = [];
      for (let i = 0; i < n / 2; i++) {
        const a = arr[i], b = arr[n - 1 - i];
        pairs.push(r % 2 === 0 ? [a, b] : [b, a]);
      }
      rounds.push(pairs);
      arr.splice(1, 0, arr.pop());
    }
    return rounds;
  }

  function poisson(lambda, r) {
    const limit = Math.exp(-lambda);
    let k = 0, p = 1;
    do { k++; p *= r(); } while (p > limit);
    return k - 1;
  }

  function matches(code, now = new Date()) {
    const names = TEAMS[code] || [];
    const r = rng(seedOf(code) + 11);
    let rounds = roundRobin(names);
    if (code === 'CL') rounds = rounds.slice(0, 8);
    else rounds = rounds.concat(rounds.map((rd) => rd.map(([h, a]) => [a, h])));

    const strength = (team) => {
      const i = names.indexOf(team);
      return i < 0 ? 0.5 : 1 - (i / names.length) * 0.8;
    };
    const anchor = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    const slots = [13.5, 16, 18.5, 24 + 15].map((h) => h * 3600e3);
    const out = [];
    rounds.forEach((pairs, ri) => {
      const roundStart = anchor + (ri - PLAYED) * 7 * 86400e3;
      pairs.forEach(([home, away], i) => {
        const m = {
          id: `${code}-${ri}-${i}`, league: code, matchday: ri + 1,
          date: new Date(roundStart + slots[i % slots.length]).toISOString(),
          home, away, homeGoals: null, awayGoals: null, status: 'scheduled'
        };
        if (ri < PLAYED) {
          const sH = strength(home), sA = strength(away);
          const lH = Math.min(3.2, Math.max(0.3, 0.9 + 1.1 * sH - 0.6 * sA + 0.25));
          const lA = Math.min(3.2, Math.max(0.3, 0.9 + 1.1 * sA - 0.6 * sH));
          m.homeGoals = poisson(lH, r);
          m.awayGoals = poisson(lA, r);
          m.status = 'finished';
        }
        out.push(m);
      });
    });
    return out;
  }

  function standings(games, teams) {
    const acc = {};
    teams.forEach((t) => { acc[t] = { played: 0, won: 0, drawn: 0, lost: 0, gf: 0, ga: 0, points: 0, results: [] }; });
    const apply = (team, scored, conceded, date) => {
      const a = acc[team] || (acc[team] = { played: 0, won: 0, drawn: 0, lost: 0, gf: 0, ga: 0, points: 0, results: [] });
      a.played++; a.gf += scored; a.ga += conceded;
      if (scored > conceded) { a.won++; a.points += 3; a.results.push([date, 'W']); }
      else if (scored === conceded) { a.drawn++; a.points += 1; a.results.push([date, 'D']); }
      else { a.lost++; a.results.push([date, 'L']); }
    };
    games.filter((m) => m.status === 'finished' && m.homeGoals != null && m.awayGoals != null).forEach((m) => {
      apply(m.home, m.homeGoals, m.awayGoals, m.date);
      apply(m.away, m.awayGoals, m.homeGoals, m.date);
    });
    return Object.entries(acc)
      .sort(([ta, a], [tb, b]) =>
        b.points - a.points || (b.gf - b.ga) - (a.gf - a.ga) || b.gf - a.gf || ta.localeCompare(tb))
      .map(([team, a], i) => ({
        position: i + 1, team, played: a.played, won: a.won, drawn: a.drawn, lost: a.lost,
        goalsFor: a.gf, goalsAgainst: a.ga, points: a.points,
        form: a.results.sort((x, y) => (x[0] < y[0] ? -1 : 1)).slice(-5).map((x) => x[1])
      }));
  }

  window.Sample = { TEAMS, players, matches, standings };
})();
