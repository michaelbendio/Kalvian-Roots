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
