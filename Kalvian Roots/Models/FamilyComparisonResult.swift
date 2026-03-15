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

        var identityMap: [PersonIdentity: [PersonCandidate]] = [:]

        let allCandidates = familySearch + juuretKalvialla + hiski

        // Group candidates by identity
        for candidate in allCandidates {
            identityMap[candidate.identity, default: []].append(candidate)
        }

        var matchResults: [Match] = []

        var fsOnly: [PersonCandidate] = []
        var jkOnly: [PersonCandidate] = []
        var hkOnly: [PersonCandidate] = []

        for (_, candidates) in identityMap {

            var fs: PersonCandidate?
            var jk: PersonCandidate?
            var hk: PersonCandidate?

            for candidate in candidates {

                switch candidate.source {

                case .familySearch:
                    fs = candidate

                case .juuretKalvialla:
                    jk = candidate

                case .hiski:
                    hk = candidate
                }
            }

            if fs != nil || jk != nil || hk != nil {

                matchResults.append(
                    Match(
                        identity: candidates.first!.identity,
                        familySearch: fs,
                        juuretKalvialla: jk,
                        hiski: hk
                    )
                )

                if fs != nil && jk == nil && hk == nil {
                    fsOnly.append(fs!)
                }

                if jk != nil && fs == nil && hk == nil {
                    jkOnly.append(jk!)
                }

                if hk != nil && fs == nil && jk == nil {
                    hkOnly.append(hk!)
                }
            }
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
