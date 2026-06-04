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
            case dated(Date, Int)
            case undated(Int)
        }

        var identityMap: [ComparisonKey: [PersonCandidate]] = [:]

        let allCandidates = familySearch + juuretKalvialla + hiski
        let datedGroups = Self.groupDatedCandidatesByChild(allCandidates.filter { $0.birthDate != nil })

        for (groupIndex, candidates) in datedGroups.enumerated() {
            guard let birthDate = candidates.first?.birthDate else {
                continue
            }
            identityMap[.dated(birthDate, groupIndex)] = candidates
        }

        for (index, candidate) in allCandidates.enumerated() where candidate.birthDate == nil {
            identityMap[.undated(index), default: []].append(candidate)
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

    private static func groupDatedCandidatesByChild(_ candidates: [PersonCandidate]) -> [[PersonCandidate]] {
        let candidatesByBirthDate = Dictionary(grouping: candidates, by: \.birthDate!)

        return candidatesByBirthDate
            .keys
            .sorted()
            .flatMap { birthDate in
                var groups: [[PersonCandidate]] = []

                for candidate in candidatesByBirthDate[birthDate] ?? [] {
                    var matchingGroupIndices: [Int] = []

                    for groupIndex in groups.indices where groups[groupIndex].contains(where: {
                        ChildNameMatcher.candidatesHaveNameMatch(candidate, $0)
                    }) {
                        matchingGroupIndices.append(groupIndex)
                    }

                    guard let firstMatch = matchingGroupIndices.first else {
                        groups.append([candidate])
                        continue
                    }

                    groups[firstMatch].append(candidate)

                    for groupIndex in matchingGroupIndices.dropFirst().reversed() {
                        groups[firstMatch].append(contentsOf: groups.remove(at: groupIndex))
                    }
                }

                return groups
            }
    }
}

private enum ChildNameMatcher {
    static func candidatesHaveNameMatch(_ left: PersonCandidate, _ right: PersonCandidate) -> Bool {
        if left.identity.canonicalName == right.identity.canonicalName {
            return true
        }

        return namesAreNear(left.rawName, right.rawName)
    }

    static func namesAreNear(_ left: String, _ right: String) -> Bool {
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
        for candidateIndex in rows.indices where candidateIndex != index && !consumedRowIndices.contains(candidateIndex) {
            let candidate = rows[candidateIndex]

            if let birthDate = row.identity.birthDate,
               candidate.identity.birthDate == birthDate,
               shouldReview(row, candidate) {
                return (
                    candidateIndex,
                    candidate,
                    reviewMessage(left: row, right: candidate, birthDate: birthDate)
                )
            }

            if shouldReviewDateDiscrepancy(row, candidate) {
                return (
                    candidateIndex,
                    candidate,
                    dateDiscrepancyReviewMessage(left: row, right: candidate)
                )
            }
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
                ChildNameMatcher.namesAreNear(leftName, rightName)
            }
        }
    }

    private static func shouldReviewDateDiscrepancy(
        _ left: FamilyComparisonResult.Match,
        _ right: FamilyComparisonResult.Match
    ) -> Bool {
        guard left.identity.canonicalName == right.identity.canonicalName,
              !left.identity.canonicalName.isEmpty,
              let leftBirthDate = left.identity.birthDate,
              let rightBirthDate = right.identity.birthDate,
              leftBirthDate != rightBirthDate else {
            return false
        }

        let leftSources = sources(for: left)
        let rightSources = sources(for: right)
        guard !leftSources.isEmpty,
              !rightSources.isEmpty,
              leftSources.isDisjoint(with: rightSources) else {
            return false
        }

        return abs(Calendar(identifier: .gregorian).dateComponents(
            [.day],
            from: leftBirthDate,
            to: rightBirthDate
        ).day ?? Int.max) <= 90
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

    private static func dateDiscrepancyReviewMessage(
        left: FamilyComparisonResult.Match,
        right: FamilyComparisonResult.Match
    ) -> String {
        let orderedRows = [left, right].sorted { first, second in
            let firstHasJuuret = first.juuretKalvialla != nil
            let secondHasJuuret = second.juuretKalvialla != nil
            return firstHasJuuret == secondHasJuuret ? false : firstHasJuuret
        }

        let sourceDetails = orderedRows
            .map(sourcePhrase(for:))
            .filter { !$0.isEmpty }
            .joined(separator: "; ")

        return "Possible same child with date discrepancy: \(sourceDetails)."
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

        if let birthDate = candidate.birthDate {
            return "\(label) has \(candidate.rawName) (\(formatDate(birthDate)))"
        }

        return "\(label) has \(candidate.rawName) (unknown birth)"
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

    var hasNoHiskiResultsNotice: Bool {
        !hiskiSearchRequests.isEmpty && !result.rows.contains { $0.hiski != nil }
    }

    static func primaryCoupleFallback(
        for family: Family,
        result: FamilyComparisonResult
    ) -> FamilyChildrenComparisonGroup? {
        guard let couple = family.primaryCouple else {
            return nil
        }

        return FamilyChildrenComparisonGroup(
            coupleIndex: 0,
            couple: couple,
            hiskiSearchRequests: [],
            result: result
        )
    }
}
