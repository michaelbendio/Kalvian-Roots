/**
 FamilyComparisonResult

 Represents the comparison of children across three sources:

 - FamilySearch
 - Juuret Kälviällä
 - HisKi

 The comparison groups PersonCandidate objects by PersonIdentity
 and determines which identities appear in which sources.
*/

import Foundation

struct FamilyComparisonResult {

    // MARK: - Match Result

    struct Match {

        let identity: PersonIdentity

        let familySearch: PersonCandidate?
        let juuretKalvialla: PersonCandidate?
        let hiski: PersonCandidate?
    }

    // MARK: - Results

    let rows: [Match]

    let matches: [Match]

    let familySearchOnly: [PersonCandidate]
    let juuretOnly: [PersonCandidate]
    let hiskiOnly: [PersonCandidate]


    // MARK: - Initialization

    init(
        familySearch: [PersonCandidate],
        juuretKalvialla: [PersonCandidate],
        hiski: [PersonCandidate]
    ) {

        enum ComparisonKey: Hashable {
            case dated(PersonIdentity)
            case undated(Int)
        }

        var identityMap: [ComparisonKey: [PersonCandidate]] = [:]

        let allCandidates = familySearch + juuretKalvialla + hiski

        // Group candidates by identity
        for (index, candidate) in allCandidates.enumerated() {
            let key: ComparisonKey = candidate.birthDate == nil
                ? .undated(index)
                : .dated(candidate.identity)
            identityMap[key, default: []].append(candidate)
        }

        var matchResults: [Match] = []
        var rowResults: [Match] = []

        var fsOnly: [PersonCandidate] = []
        var jkOnly: [PersonCandidate] = []
        var hkOnly: [PersonCandidate] = []

        for (_, candidates) in identityMap {
            let fsCandidates = candidates.filter(\.isFromFamilySearch)
            let jkCandidates = candidates.filter(\.isFromJuuret)
            let hkCandidates = candidates.filter(\.isFromHiski)

            let rowCount = max(fsCandidates.count, jkCandidates.count, hkCandidates.count)

            guard rowCount > 0 else {
                continue
            }

            for index in 0..<rowCount {
                let fs = fsCandidates.indices.contains(index) ? fsCandidates[index] : nil
                let jk = jkCandidates.indices.contains(index) ? jkCandidates[index] : nil
                let hk = hkCandidates.indices.contains(index) ? hkCandidates[index] : nil
                let identity = fs?.identity ?? jk?.identity ?? hk!.identity

                if fs != nil && jk == nil && hk == nil {
                    fsOnly.append(fs!)
                }

                if jk != nil && fs == nil && hk == nil {
                    jkOnly.append(jk!)
                }

                if hk != nil && fs == nil && jk == nil {
                    hkOnly.append(hk!)
                }

                guard fs != nil || jk != nil || hk != nil else {
                    continue
                }

                let row = Match(
                    identity: identity,
                    familySearch: fs,
                    juuretKalvialla: jk,
                    hiski: hk
                )
                rowResults.append(row)

                let presentSourceCount = [fs, jk, hk].filter { $0 != nil }.count
                if presentSourceCount >= 2 {
                    matchResults.append(row)
                }
            }
        }

        self.rows = rowResults.sorted {
            ($0.identity.birthDate ?? .distantFuture) <
            ($1.identity.birthDate ?? .distantFuture)
        }

        self.matches = matchResults.sorted {
            ($0.identity.birthDate ?? .distantFuture) <
            ($1.identity.birthDate ?? .distantFuture)
        }

        self.familySearchOnly = fsOnly
        self.juuretOnly = jkOnly
        self.hiskiOnly = hkOnly
    }
}

struct FamilyChildrenComparisonGroup {
    let coupleIndex: Int
    let couple: Couple
    let hiskiSearchRequests: [HiskiService.FamilyBirthSearchRequest]
    let result: FamilyComparisonResult
}

enum TikkanenSixDevelopmentData {
    static let familyId = "TIKKANEN 6"

    static func isEnabled(for family: Family) -> Bool {
        family.familyId.uppercased() == familyId
    }

    static func makeComparisonGroups(
        for family: Family,
        nameManager: NameEquivalenceManager,
        hiskiRowsByCouple: [Int: [HiskiService.HiskiFamilyBirthRow]] = [:]
    ) -> [FamilyChildrenComparisonGroup] {
        guard isEnabled(for: family) else {
            return []
        }

        let comparisonService = FamilyComparisonService(nameManager: nameManager)
        let hiskiService = HiskiService(nameEquivalenceManager: nameManager)
        hiskiService.setCurrentFamily(family.familyId)

        return family.couples.enumerated().map { index, couple in
            let marriageYear = extractYear(from: couple.fullMarriageDate ?? couple.marriageDate)
            let requests = marriageYear.flatMap {
                try? hiskiService.buildFamilyBirthSearchRequests(
                    fatherName: couple.husband.name,
                    fatherPatronymic: couple.husband.patronymic,
                    motherName: couple.wife.name,
                    motherPatronymic: couple.wife.patronymic,
                    marriageYear: $0
                )
            }.map { Array($0.prefix(1)) } ?? []

            let result = comparisonService.compareChildren(
                juuretChildren: couple.children,
                hiskiRows: hiskiRowsByCouple[index] ?? [],
                familySearchChildren: familySearchChildren(
                    forCoupleAt: index,
                    hiskiRows: hiskiRowsByCouple[index] ?? [],
                    nameManager: nameManager
                )
            )

            return FamilyChildrenComparisonGroup(
                coupleIndex: index,
                couple: couple,
                hiskiSearchRequests: requests,
                result: result
            )
        }
    }
}

private extension TikkanenSixDevelopmentData {
    static func familySearchChildren(
        forCoupleAt index: Int,
        hiskiRows: [HiskiService.HiskiFamilyBirthRow],
        nameManager: NameEquivalenceManager
    ) -> [FamilySearchChild] {
        familySearchChildren(forCoupleAt: index).map { child in
            guard isYearOnly(child.birthDate),
                  let hiskiBirthDate = matchingHiskiBirthDate(
                    for: child,
                    in: hiskiRows,
                    nameManager: nameManager
                  ) else {
                return child
            }

            var updated = child
            updated.birthDate = hiskiBirthDate
            return updated
        }
    }

    static func familySearchChildren(forCoupleAt index: Int) -> [FamilySearchChild] {
        switch index {
        case 0:
            return [
                familySearchChild(id: "LXSP-RTS", name: "Tikkanen", birthDate: "1739", deathDate: "1739"),
                familySearchChild(id: "LXSP-T4T", name: "Carin Tikkanen", birthDate: "1740", deathDate: "1740")
            ]
        case 1:
            return [
                familySearchChild(id: "M88C-9G5", name: "Elisabeth Tikkanen", birthDate: "1747", deathDate: "1747"),
                familySearchChild(id: "M8ZT-H6K", name: "Anna Eriksson", birthDate: "1748"),
                familySearchChild(id: "M8ZP-9VD", name: "Brita Eriksson", birthDate: "20.05.1750", deathDate: "1750"),
                familySearchChild(id: "M88M-KZZ", name: "Johannes Eriksson", birthDate: "27.11.1751"),
                familySearchChild(id: "M8ZL-2C1", name: "Erik Eriksson", birthDate: "06.02.1753", deathDate: "03.06.1785")
            ]
        case 2:
            return [
                familySearchChild(id: "M8Z1-C8M", name: "Elias Tikkanen", birthDate: "1755", deathDate: "1755"),
                familySearchChild(id: "M8ZN-Q6S", name: "Matts Tikkanen", birthDate: "1755", deathDate: "1755"),
                familySearchChild(id: "LHH6-W2P", name: "Matts Tikkanen", birthDate: "14.03.1756", deathDate: "1829"),
                familySearchChild(id: "M8ZB-PGR", name: "Michel Tikkanen", birthDate: "05.03.1757", deathDate: "1809"),
                familySearchChild(id: "M883-K1G", name: "Gustaf Tikkanen", birthDate: "1758", deathDate: "1758"),
                familySearchChild(id: "K2TZ-DY4", name: "Gustav Tikkanen", birthDate: "13.09.1759", deathDate: "1825"),
                familySearchChild(id: "KHM5-VHL", name: "Elias Tikkanen", birthDate: "14.12.1760"),
                familySearchChild(id: "M88Z-4M5", name: "Jacob Eriksson", birthDate: "1762", deathDate: "1762"),
                familySearchChild(id: "M8Z5-CXJ", name: "Brita Tikkanen", birthDate: "04.12.1763"),
                familySearchChild(id: "M887-WG3", name: "Anders Eriksson Tikkanen", birthDate: "07.03.1765", deathDate: "1838"),
                familySearchChild(id: "M8ZN-M45", name: "Malin Eriksdotter", birthDate: "1766", deathDate: "1766"),
                familySearchChild(id: "GW9B-8JZ", name: "Elisabet Eriksdr. Tikkanen", birthDate: "28.11.1767", deathDate: "1843"),
                familySearchChild(id: "M88Z-4SX", name: "Jacob Eriksson", birthDate: "24.03.1769"),
                familySearchChild(id: "M8ZK-MCM", name: "Maria Eriksdotter", birthDate: "31.05.1770", deathDate: "1851"),
                familySearchChild(id: "KZXH-GLC", name: "Kaarin Erikintytär Tikkanen", birthDate: "16.06.1773", deathDate: "1828"),
                familySearchChild(id: "M8ZY-KJ8", name: "Isaac Eriksson", birthDate: "1774", deathDate: "1774"),
                familySearchChild(id: "M887-1Q4", name: "Abram Eriksson", birthDate: "25.11.1774", deathDate: "1834"),
                familySearchChild(id: "M88M-7ZH", name: "Hinric Eriksson", birthDate: "1777", deathDate: "1777")
            ]
        default:
            return []
        }
    }

    static func matchingHiskiBirthDate(
        for child: FamilySearchChild,
        in rows: [HiskiService.HiskiFamilyBirthRow],
        nameManager: NameEquivalenceManager
    ) -> String? {
        let childName = comparisonGivenName(from: child.name)
        let childYear = extractYear(from: child.birthDate)

        return rows.first { row in
            guard extractYear(from: row.birthDate) == childYear else {
                return false
            }

            return nameManager.areNamesEquivalent(childName, row.childName)
        }?.birthDate
    }

    static func comparisonGivenName(from name: String) -> String {
        name
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init) ?? name
    }

    static func isYearOnly(_ rawDate: String?) -> Bool {
        guard let rawDate else {
            return false
        }

        return rawDate.range(of: #"^\d{4}$"#, options: .regularExpression) != nil
    }

    static func familySearchChild(
        id: String,
        name: String,
        birthDate: String,
        deathDate: String? = nil
    ) -> FamilySearchChild {
        FamilySearchChild(
            id: id,
            name: name,
            birthDate: birthDate,
            deathDate: deathDate
        )
    }

    static func extractYear(from rawDate: String?) -> Int? {
        guard let rawDate,
              let yearRange = rawDate.range(of: #"\b\d{4}\b"#, options: .regularExpression) else {
            return nil
        }

        return Int(rawDate[yearRange])
    }
}
