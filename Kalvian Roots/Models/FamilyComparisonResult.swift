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

struct FamilyComparisonReviewNote: Equatable, Identifiable {
    let rowIndex: Int
    let message: String

    var id: Int {
        rowIndex
    }
}

struct FamilyComparisonDisplayRow: Identifiable {
    let sourceRowIndices: [Int]
    let match: FamilyComparisonResult.Match
    let reviewNote: FamilyComparisonReviewNote?

    var id: String {
        sourceRowIndices.map(String.init).joined(separator: "-")
    }
}

enum FamilyComparisonReviewDetector {
    static func displayRows(for rows: [FamilyComparisonResult.Match]) -> [FamilyComparisonDisplayRow] {
        var consumedRowIndices: Set<Int> = []
        var displayRows: [FamilyComparisonDisplayRow] = []

        for (index, row) in rows.enumerated() {
            guard !consumedRowIndices.contains(index) else {
                continue
            }

            if let reviewPair = firstReviewPair(for: index, row: row, rows: rows, consumedRowIndices: consumedRowIndices) {
                consumedRowIndices.insert(index)
                consumedRowIndices.insert(reviewPair.index)

                displayRows.append(
                    FamilyComparisonDisplayRow(
                        sourceRowIndices: [index, reviewPair.index].sorted(),
                        match: mergedMatch(row, reviewPair.row),
                        reviewNote: FamilyComparisonReviewNote(
                            rowIndex: index,
                            message: reviewPair.message
                        )
                    )
                )
            } else {
                consumedRowIndices.insert(index)
                displayRows.append(
                    FamilyComparisonDisplayRow(
                        sourceRowIndices: [index],
                        match: row,
                        reviewNote: nil
                    )
                )
            }
        }

        return displayRows.sorted {
            ($0.match.identity.birthDate ?? .distantFuture) <
            ($1.match.identity.birthDate ?? .distantFuture)
        }
    }

    static func notes(for rows: [FamilyComparisonResult.Match]) -> [Int: FamilyComparisonReviewNote] {
        let rowsByBirthDate = Dictionary(
            grouping: rows.enumerated().filter { $0.element.identity.birthDate != nil },
            by: { $0.element.identity.birthDate! }
        )

        var notes: [Int: FamilyComparisonReviewNote] = [:]

        for (birthDate, datedRows) in rowsByBirthDate where datedRows.count > 1 {
            for leftOffset in datedRows.indices {
                for rightOffset in datedRows.indices where rightOffset > leftOffset {
                    let left = datedRows[leftOffset]
                    let right = datedRows[rightOffset]

                    guard shouldReview(left.element, right.element) else {
                        continue
                    }

                    let message = reviewMessage(
                        left: left.element,
                        right: right.element,
                        birthDate: birthDate
                    )

                    notes[left.offset] = notes[left.offset] ?? FamilyComparisonReviewNote(
                        rowIndex: left.offset,
                        message: message
                    )
                    notes[right.offset] = notes[right.offset] ?? FamilyComparisonReviewNote(
                        rowIndex: right.offset,
                        message: message
                    )
                }
            }
        }

        return notes
    }

    private static func firstReviewPair(
        for index: Int,
        row: FamilyComparisonResult.Match,
        rows: [FamilyComparisonResult.Match],
        consumedRowIndices: Set<Int>
    ) -> (index: Int, row: FamilyComparisonResult.Match, message: String)? {
        guard let birthDate = row.identity.birthDate else {
            return nil
        }

        for candidateIndex in rows.indices where candidateIndex != index && !consumedRowIndices.contains(candidateIndex) {
            let candidate = rows[candidateIndex]

            guard candidate.identity.birthDate == birthDate,
                  shouldReview(row, candidate) else {
                continue
            }

            return (
                candidateIndex,
                candidate,
                reviewMessage(left: row, right: candidate, birthDate: birthDate)
            )
        }

        return nil
    }

    private static func mergedMatch(
        _ left: FamilyComparisonResult.Match,
        _ right: FamilyComparisonResult.Match
    ) -> FamilyComparisonResult.Match {
        let mergedIdentity = left.juuretKalvialla?.identity
            ?? right.juuretKalvialla?.identity
            ?? left.familySearch?.identity
            ?? right.familySearch?.identity
            ?? left.hiski?.identity
            ?? right.hiski?.identity
            ?? right.identity

        return FamilyComparisonResult.Match(
            identity: mergedIdentity,
            familySearch: left.familySearch ?? right.familySearch,
            juuretKalvialla: left.juuretKalvialla ?? right.juuretKalvialla,
            hiski: left.hiski ?? right.hiski
        )
    }

    private static func shouldReview(
        _ left: FamilyComparisonResult.Match,
        _ right: FamilyComparisonResult.Match
    ) -> Bool {
        let leftSources = sources(for: left)
        let rightSources = sources(for: right)

        guard !leftSources.isEmpty,
              !rightSources.isEmpty,
              leftSources.isDisjoint(with: rightSources) else {
            return false
        }

        return candidateNames(for: left).contains { leftName in
            candidateNames(for: right).contains { rightName in
                namesAreNear(leftName, rightName)
            }
        }
    }

    private static func sources(for row: FamilyComparisonResult.Match) -> Set<String> {
        var sources: Set<String> = []
        if row.juuretKalvialla != nil {
            sources.insert("Juuret")
        }
        if row.familySearch != nil {
            sources.insert("FamilySearch")
        }
        if row.hiski != nil {
            sources.insert("HisKi")
        }
        return sources
    }

    private static func candidateNames(for row: FamilyComparisonResult.Match) -> [String] {
        [
            row.juuretKalvialla?.rawName,
            row.familySearch?.rawName,
            row.hiski?.rawName
        ].compactMap { $0 }
    }

    private static func namesAreNear(_ left: String, _ right: String) -> Bool {
        guard let leftToken = comparableGivenToken(from: left),
              let rightToken = comparableGivenToken(from: right) else {
            return false
        }

        if leftToken == rightToken {
            return true
        }

        let shorterCount = min(leftToken.count, rightToken.count)
        guard shorterCount >= 4 else {
            return false
        }

        if leftToken.hasPrefix(rightToken) || rightToken.hasPrefix(leftToken) {
            return true
        }

        return commonPrefixCount(leftToken, rightToken) >= 5
    }

    private static func comparableGivenToken(from name: String) -> String? {
        let token = name
            .split { !$0.isLetter }
            .first
            .map(String.init)?
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fi_FI"))
            .filter(\.isLetter)

        guard let token, !token.isEmpty else {
            return nil
        }

        return token
    }

    private static func commonPrefixCount(_ left: String, _ right: String) -> Int {
        var count = 0
        for (leftCharacter, rightCharacter) in zip(left, right) {
            guard leftCharacter == rightCharacter else {
                break
            }
            count += 1
        }
        return count
    }

    private static func reviewMessage(
        left: FamilyComparisonResult.Match,
        right: FamilyComparisonResult.Match,
        birthDate: Date
    ) -> String {
        let orderedRows = [left, right].sorted { first, second in
            let firstHasHiski = first.hiski != nil
            let secondHasHiski = second.hiski != nil
            return firstHasHiski == secondHasHiski ? false : !firstHasHiski
        }

        let sourceDetails = orderedRows
            .map(sourcePhrase(for:))
            .filter { !$0.isEmpty }
            .joined(separator: "; ")

        return "Possible same child on \(formatDate(birthDate)): \(sourceDetails)."
    }

    private static func sourcePhrase(for row: FamilyComparisonResult.Match) -> String {
        if let juuret = row.juuretKalvialla,
           let familySearch = row.familySearch,
           juuret.rawName == familySearch.rawName,
           row.hiski == nil {
            return "Juuret and FamilySearch have \(juuret.rawName)"
        }

        let phrases = [
            sourcePhrase(label: "Juuret", candidate: row.juuretKalvialla),
            sourcePhrase(label: "FamilySearch", candidate: row.familySearch),
            sourcePhrase(label: "HisKi", candidate: row.hiski)
        ].compactMap { $0 }

        return phrases.joined(separator: "; ")
    }

    private static func sourcePhrase(label: String, candidate: PersonCandidate?) -> String? {
        guard let candidate else {
            return nil
        }

        return "\(label) has \(candidate.rawName)"
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "dd MMM yyyy"
        return formatter.string(from: date)
    }
}

struct FamilyChildrenComparisonGroup {
    let coupleIndex: Int
    let couple: Couple
    let hiskiSearchRequests: [HiskiService.FamilyBirthSearchRequest]
    let result: FamilyComparisonResult

    var displayRows: [FamilyComparisonDisplayRow] {
        FamilyComparisonReviewDetector.displayRows(for: result.rows)
    }
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
