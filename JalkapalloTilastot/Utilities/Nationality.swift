import Foundation

/// Kansallisuusnimi (football-data.org) -> lippuemoji, sekä pelaajanimien vertailu lähteiden välillä.
enum Nationality {
    private static let codes: [String: String] = [
        "Albania": "AL",
        "Algeria": "DZ",
        "Angola": "AO",
        "Argentina": "AR",
        "Armenia": "AM",
        "Australia": "AU",
        "Austria": "AT",
        "Azerbaijan": "AZ",
        "Belarus": "BY",
        "Belgium": "BE",
        "Benin": "BJ",
        "Bolivia": "BO",
        "Bosnia-Herzegovina": "BA",
        "Bosnia and Herzegovina": "BA",
        "Brazil": "BR",
        "Bulgaria": "BG",
        "Burkina Faso": "BF",
        "Burundi": "BI",
        "Cameroon": "CM",
        "Canada": "CA",
        "Cape Verde": "CV",
        "Cape Verde Islands": "CV",
        "Central African Republic": "CF",
        "Chile": "CL",
        "China": "CN",
        "China PR": "CN",
        "Colombia": "CO",
        "Comoros": "KM",
        "Congo": "CG",
        "Congo DR": "CD",
        "DR Congo": "CD",
        "Costa Rica": "CR",
        "Croatia": "HR",
        "Cuba": "CU",
        "Curacao": "CW",
        "Curaçao": "CW",
        "Cyprus": "CY",
        "Czech Republic": "CZ",
        "Czechia": "CZ",
        "Denmark": "DK",
        "Dominican Republic": "DO",
        "Ecuador": "EC",
        "Egypt": "EG",
        "Equatorial Guinea": "GQ",
        "Eritrea": "ER",
        "Estonia": "EE",
        "Ethiopia": "ET",
        "Faroe Islands": "FO",
        "Finland": "FI",
        "France": "FR",
        "Gabon": "GA",
        "Gambia": "GM",
        "Georgia": "GE",
        "Germany": "DE",
        "Ghana": "GH",
        "Greece": "GR",
        "Guinea": "GN",
        "Guinea-Bissau": "GW",
        "Haiti": "HT",
        "Honduras": "HN",
        "Hungary": "HU",
        "Iceland": "IS",
        "India": "IN",
        "Indonesia": "ID",
        "Iran": "IR",
        "Iraq": "IQ",
        "Ireland": "IE",
        "Republic of Ireland": "IE",
        "Israel": "IL",
        "Italy": "IT",
        "Ivory Coast": "CI",
        "Côte d'Ivoire": "CI",
        "Cote d'Ivoire": "CI",
        "Jamaica": "JM",
        "Japan": "JP",
        "Jordan": "JO",
        "Kazakhstan": "KZ",
        "Kenya": "KE",
        "Kosovo": "XK",
        "Latvia": "LV",
        "Lebanon": "LB",
        "Liberia": "LR",
        "Libya": "LY",
        "Lithuania": "LT",
        "Luxembourg": "LU",
        "Madagascar": "MG",
        "Mali": "ML",
        "Malta": "MT",
        "Mauritania": "MR",
        "Mexico": "MX",
        "Moldova": "MD",
        "Montenegro": "ME",
        "Morocco": "MA",
        "Mozambique": "MZ",
        "Namibia": "NA",
        "Netherlands": "NL",
        "New Zealand": "NZ",
        "Niger": "NE",
        "Nigeria": "NG",
        "North Macedonia": "MK",
        "Norway": "NO",
        "Panama": "PA",
        "Paraguay": "PY",
        "Peru": "PE",
        "Philippines": "PH",
        "Poland": "PL",
        "Portugal": "PT",
        "Romania": "RO",
        "Russia": "RU",
        "Rwanda": "RW",
        "Saudi Arabia": "SA",
        "Senegal": "SN",
        "Serbia": "RS",
        "Sierra Leone": "SL",
        "Slovakia": "SK",
        "Slovenia": "SI",
        "South Africa": "ZA",
        "South Korea": "KR",
        "Korea Republic": "KR",
        "Spain": "ES",
        "Suriname": "SR",
        "Sweden": "SE",
        "Switzerland": "CH",
        "Syria": "SY",
        "Tanzania": "TZ",
        "Togo": "TG",
        "Trinidad and Tobago": "TT",
        "Tunisia": "TN",
        "Turkey": "TR",
        "Türkiye": "TR",
        "Uganda": "UG",
        "Ukraine": "UA",
        "United States": "US",
        "USA": "US",
        "Uruguay": "UY",
        "Uzbekistan": "UZ",
        "Venezuela": "VE",
        "Zambia": "ZM",
        "Zimbabwe": "ZW"
    ]

    private static let subdivisions: [String: String] = [
        "England": "gbeng", "Scotland": "gbsct", "Wales": "gbwls", "Northern Ireland": "gbnir"
    ]

    static func flag(for country: String) -> String {
        if let tag = subdivisions[country], tag != "gbnir" { return tagFlag(tag) }
        if country == "Northern Ireland" { return "\u{1F1EC}\u{1F1E7}" }
        guard let code = codes[country] else { return "" }
        return code.unicodeScalars
            .compactMap { UnicodeScalar(0x1F1E6 + $0.value - 65) }
            .map { String($0) }
            .joined()
    }

    /// Alueliput (Englanti, Skotlanti, Wales) ovat tagisekvenssejä: musta lippu + kirjaintagit + lopetus.
    private static func tagFlag(_ tag: String) -> String {
        var scalars: [UnicodeScalar] = [UnicodeScalar(0x1F3F4)!]
        for char in tag.unicodeScalars {
            if let s = UnicodeScalar(0xE0000 + char.value) { scalars.append(s) }
        }
        scalars.append(UnicodeScalar(0xE007F)!)
        return String(String.UnicodeScalarView(scalars))
    }

    static func tokens(_ name: String) -> Set<String> {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        return Set(folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 1 })
    }

    /// "Kylian Mbappe-Lottin" ja "Kylian Mbappé" kuuluvat yhteen: toisen nimen sanat ovat toisen osajoukko.
    static func namesMatch(_ a: Set<String>, _ b: Set<String>) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a.isSubset(of: b) || b.isSubset(of: a)
    }
}
