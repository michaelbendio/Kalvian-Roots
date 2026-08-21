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
import KalvianRootsCore

typealias FamilyComparisonResult = KalvianRootsCore.FamilyComparisonResult

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
                PersonNameComparison.namesAreNear(leftName, rightName)
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

        let calendar = Calendar(identifier: .gregorian)
        if abs(calendar.dateComponents(
            [.day],
            from: leftBirthDate,
            to: rightBirthDate
        ).day ?? Int.max) <= 90 {
            return true
        }

        let leftComponents = calendar.dateComponents([.year, .day], from: leftBirthDate)
        let rightComponents = calendar.dateComponents([.year, .day], from: rightBirthDate)
        return leftComponents.year == rightComponents.year &&
            leftComponents.day == rightComponents.day
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
