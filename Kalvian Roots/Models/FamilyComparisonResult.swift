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

struct FamilySearchCoupleChildrenMatch: Equatable {
    let coupleIndex: Int
    let spouseGroupIndex: Int?
    let children: [FamilySearchChild]
    let debugSummary: String
}

enum TikkanenSixDevelopmentData {
    static let familyId = "TIKKANEN 6"

    static func isEnabled(for family: Family) -> Bool {
        family.familyId.uppercased() == familyId
    }

    static func makeComparisonGroups(
        for family: Family,
        nameManager: NameEquivalenceManager,
        hiskiRowsByCouple: [Int: [HiskiService.HiskiFamilyBirthRow]] = [:],
        familySearchChildrenByCouple: [Int: [FamilySearchChild]] = [:]
    ) -> [FamilyChildrenComparisonGroup] {
        guard isEnabled(for: family) else {
            return []
        }

        let comparisonService = FamilyComparisonService(nameManager: nameManager)
        let hiskiService = HiskiService(nameEquivalenceManager: nameManager)
        hiskiService.setCurrentFamily(family.familyId)

        return family.couples.enumerated().map { index, couple in
            let marriageYear = extractYear(from: couple.fullMarriageDate ?? couple.marriageDate)
            let requests: [HiskiService.FamilyBirthSearchRequest]
            if let marriageYear {
                let hiskiEndYear = HiskiService.familyBirthEndYear(
                    marriageYear: marriageYear,
                    husbandDeathDate: couple.husband.deathDate,
                    wifeDeathDate: couple.wife.deathDate
                )
                let searchRequests = try? hiskiService.buildFamilyBirthSearchRequests(
                    fatherName: couple.husband.name,
                    fatherPatronymic: couple.husband.patronymic,
                    motherName: couple.wife.name,
                    motherPatronymic: couple.wife.patronymic,
                    marriageYear: marriageYear,
                    endYear: hiskiEndYear
                )
                requests = searchRequests.map { Array($0.prefix(1)) } ?? []
            } else {
                requests = []
            }

            let result = comparisonService.compareChildren(
                juuretChildren: couple.children,
                hiskiRows: hiskiRowsByCouple[index] ?? [],
                familySearchChildren: familySearchChildren(
                    forCoupleAt: index,
                    childrenByCouple: familySearchChildrenByCouple,
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

    static func matchFamilySearchChildrenByCouple(
        for family: Family,
        extraction: FamilySearchFamilyExtraction?
    ) -> [FamilySearchCoupleChildrenMatch] {
        guard let extraction else {
            return family.couples.indices.map { index in
                FamilySearchCoupleChildrenMatch(
                    coupleIndex: index,
                    spouseGroupIndex: nil,
                    children: [],
                    debugSummary: "FamilySearch spouse group not matched to couple \(index + 1): no stored extraction"
                )
            }
        }

        guard extraction.isSuccessful else {
            let status = extraction.status ?? "unknown"
            return family.couples.indices.map { index in
                FamilySearchCoupleChildrenMatch(
                    coupleIndex: index,
                    spouseGroupIndex: nil,
                    children: [],
                    debugSummary: "FamilySearch spouse group not matched to couple \(index + 1): extraction status \(status)"
                )
            }
        }

        guard let spouseGroups = extraction.spouseGroups, !spouseGroups.isEmpty else {
            return family.couples.indices.map { index in
                let children = family.couples.count == 1 ? extraction.children : []
                let detail = family.couples.count == 1
                    ? "fallback to top-level extracted children"
                    : "no spouse groups in extraction"
                return FamilySearchCoupleChildrenMatch(
                    coupleIndex: index,
                    spouseGroupIndex: nil,
                    children: children,
                    debugSummary: "FamilySearch spouse group not matched to couple \(index + 1): \(detail), children \(children.count)"
                )
            }
        }

        let familySearchIdCounts = family.couples
            .flatMap { normalizedFamilySearchIds(for: $0) }
            .reduce(into: [String: Int]()) { counts, id in
                counts[id, default: 0] += 1
            }

        var usedGroupIndexes = Set<Int>()
        return family.couples.enumerated().map { index, couple in
            let coupleIds = normalizedFamilySearchIds(for: couple)
            let preferredIds = coupleIds.filter { familySearchIdCounts[$0, default: 0] == 1 }
            let idsForMatching: [String]
            if preferredIds.isEmpty, family.couples.count > 1 {
                idsForMatching = []
            } else {
                idsForMatching = preferredIds.isEmpty ? coupleIds : preferredIds
            }

            if let match = bestSpouseGroupMatch(
                spouseGroups: spouseGroups,
                candidateParentIds: idsForMatching,
                marriageYear: extractYear(from: couple.fullMarriageDate ?? couple.marriageDate),
                usedGroupIndexes: usedGroupIndexes
            ) {
                usedGroupIndexes.insert(match.groupIndex)
                let matchDetail: String
                if let matchedFamilySearchId = match.matchedFamilySearchId {
                    matchDetail = " by parent FamilySearch ID \(matchedFamilySearchId)"
                } else if let matchedMarriageYear = match.matchedMarriageYear {
                    matchDetail = " by marriage year \(matchedMarriageYear)"
                } else {
                    matchDetail = ""
                }
                let declared = spouseGroups[match.groupIndex].declaredChildCount.map(String.init) ?? "unknown"
                return FamilySearchCoupleChildrenMatch(
                    coupleIndex: index,
                    spouseGroupIndex: match.groupIndex,
                    children: spouseGroups[match.groupIndex].children,
                    debugSummary: "FamilySearch spouse group \(match.groupIndex + 1) matched to couple \(index + 1)\(matchDetail): declared children \(declared), extracted children \(spouseGroups[match.groupIndex].children.count)"
                )
            }

            return FamilySearchCoupleChildrenMatch(
                coupleIndex: index,
                spouseGroupIndex: nil,
                children: [],
                debugSummary: "FamilySearch spouse group not matched to couple \(index + 1): no unused spouse group contains a couple-specific FamilySearch ID or unique marriage year"
            )
        }
    }
}

private extension TikkanenSixDevelopmentData {
    struct SpouseGroupMatch {
        let groupIndex: Int
        let matchedFamilySearchId: String?
        let matchedMarriageYear: Int?
    }

    static func familySearchChildren(
        forCoupleAt index: Int,
        childrenByCouple: [Int: [FamilySearchChild]],
        hiskiRows: [HiskiService.HiskiFamilyBirthRow],
        nameManager: NameEquivalenceManager
    ) -> [FamilySearchChild] {
        (childrenByCouple[index] ?? []).map { child in
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

    static func extractYear(from rawDate: String?) -> Int? {
        guard let rawDate,
              let yearRange = rawDate.range(of: #"\b\d{4}\b"#, options: .regularExpression) else {
            return nil
        }

        return Int(rawDate[yearRange])
    }

    static func normalizedFamilySearchIds(for couple: Couple) -> [String] {
        [
            normalizedFamilySearchId(couple.husband.familySearchId),
            normalizedFamilySearchId(couple.wife.familySearchId)
        ]
            .compactMap { $0 }
    }

    static func normalizedFamilySearchId(_ id: String?) -> String? {
        guard let id else {
            return nil
        }

        let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalized.isEmpty ? nil : normalized
    }

    static func bestSpouseGroupMatch(
        spouseGroups: [FamilySearchSpouseGroup],
        candidateParentIds: [String],
        marriageYear: Int?,
        usedGroupIndexes: Set<Int>
    ) -> SpouseGroupMatch? {
        for (index, group) in spouseGroups.enumerated() where !usedGroupIndexes.contains(index) {
            let spouseIds = Set(group.spouses.compactMap { normalizedFamilySearchId($0.id) })
            if let matchedId = candidateParentIds.first(where: { spouseIds.contains($0) }) {
                return SpouseGroupMatch(
                    groupIndex: index,
                    matchedFamilySearchId: matchedId,
                    matchedMarriageYear: nil
                )
            }
        }

        if let marriageYear {
            let marriageYearMatches = spouseGroups.enumerated().compactMap { index, group -> Int? in
                guard !usedGroupIndexes.contains(index),
                      extractYear(from: group.marriage?.date) == marriageYear else {
                    return nil
                }
                return index
            }

            if marriageYearMatches.count == 1, let groupIndex = marriageYearMatches.first {
                return SpouseGroupMatch(
                    groupIndex: groupIndex,
                    matchedFamilySearchId: nil,
                    matchedMarriageYear: marriageYear
                )
            }
        }

        return nil
    }
}
