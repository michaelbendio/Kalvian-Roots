//
//  FamilyContentView.swift
//  Kalvian Roots
//
//  Phase 4: Family Display Layout with authentic monospace appearance
//  Matches the UI mockup specification
//

import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/**
 * Family content display with authentic genealogy book appearance
 *
 * Phase 4 Implementation:
 * - Monospace font throughout (like Courier New)
 * - Tight line spacing (1.3) matching the mockup
 * - Off-white background (#fefdf8) for warmth
 * - Proper family structure ordering
 * - Minimal gaps between sections for density
 */
struct FamilyContentView: View {
    @Environment(JuuretApp.self) private var juuretApp
    let family: Family
    
    // Citation and Hiski handlers
    let onShowCitation: (String) -> Void
    let onShowHiski: (String) -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 1. Family ID + page references
                familyHeader
                    .padding(.bottom, 12)
                
                // 2. Parent lines (primary couple)
                if let couple = family.primaryCouple {
                    parentLines(couple: couple)
                    
                    // 3. Marriage date line
                    if let marriageDate = couple.fullMarriageDate ?? couple.marriageDate {
                        marriageLine(date: marriageDate, couple: couple)
                            .padding(.top, 2)
                    }
                    
                    // 4. "Lapset" header + children
                    if !couple.children.isEmpty {
                        childrenSection(children: couple.children)
                            .padding(.top, 8)
                    }
                    
                    // Children died in infancy
                    if let died = couple.childrenDiedInfancy, died > 0 {
                        Text("Lapsena kuollut \(died).")
                            .applyFamilyLineStyle()
                            .foregroundColor(.secondary)
                            .italic()
                            .padding(.top, 4)
                    }
                }
                
                // 6. Additional spouses (II puoliso, III puoliso, etc.)
                if family.couples.count > 1 {
                    additionalSpouses()
                        .padding(.top, 12)
                }
                
                // 7. Notes
                if !family.notes.isEmpty {
                    notesSection()
                        .padding(.top, 12)
                }
                
                // 8. Note definitions (* ** etc.)
                // Note definitions (* **)  etc.)
                if !family.noteDefinitions.isEmpty {
                    noteDefinitionsSection()
                        .padding(.top, 4)
                }

                if !juuretApp.comparisonReport.isEmpty {
                    GroupBox("Juuret + HisKi Report") {
                        Text(juuretApp.comparisonReport)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.top, 12)
                }

                if !juuretApp.hiskiCitationProposals.isEmpty {
                    GroupBox("HisKi Citation Proposals") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(juuretApp.hiskiCitationProposals, id: \.citationURL) { proposal in
                                let shortCitation = proposal.shortCitationString(from: proposal.citationURL)

                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(proposal.displayName)
                                        .foregroundStyle(.primary)

                                    Text("—")
                                        .foregroundStyle(.secondary)

                                    Button {
                                        copyToClipboard(shortCitation)
                                    } label: {
                                        Text(shortCitation)
                                            .underline()
                                            .foregroundStyle(Color(hex: "0066cc"))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(.top, 12)
                }

                if shouldRenderFamilySearchComparisonUI {
                    familySearchComparisonPanel
                        .padding(.top, 12)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(hex: "fefdf8"))
    }

    private var shouldRenderFamilySearchComparisonUI: Bool {
        let shouldRender = juuretApp.familySearchComparisonResult != nil ||
            !juuretApp.familySearchComparisonDebugMessage.isEmpty

        logInfo(
            .ui,
            "🧪 comparison UI render condition evaluated: \(shouldRender) " +
            "(resultRows: \(juuretApp.familySearchComparisonResult?.rows.count ?? 0), " +
            "message: \(juuretApp.familySearchComparisonDebugMessage))"
        )

        return shouldRender
    }

    private var familySearchComparisonPanel: some View {
        GroupBox("Juuret / HisKi / FamilySearch Children Comparison") {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    copyToClipboard(familySearchComparisonClipboardText)
                } label: {
                    Label("Copy comparison text", systemImage: "doc.on.doc")
                        .font(.system(.caption, design: .monospaced))
                }
                .buttonStyle(.bordered)

                if juuretApp.currentFamilySearchExtractorPageURL != nil {
                    Button {
                        juuretApp.openCurrentFamilySearchExtractorPage()
                    } label: {
                        Label("Open FamilySearch", systemImage: "safari")
                            .font(.system(.caption, design: .monospaced))
                    }
                    .buttonStyle(.bordered)
                }

                Text(juuretApp.familySearchComparisonDebugMessage.isEmpty
                    ? "Comparison not triggered"
                    : juuretApp.familySearchComparisonDebugMessage)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if !juuretApp.familySearchComparisonDebugLines.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(juuretApp.familySearchComparisonDebugLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                if juuretApp.familySearchComparisonDebugMessage == "FamilySearch comparison not yet available" {
                    Text("Open the FamilySearch person Details page, click the reusable Kalvian Roots FamilySearch Extractor bookmarklet in Atlas, then return here.")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let result = juuretApp.familySearchComparisonResult, !result.rows.isEmpty {
                    familySearchComparisonTable(rows: result.rows)
                } else {
                    Text(juuretApp.familySearchComparisonDebugMessage.isEmpty
                        ? "Comparison not triggered"
                        : juuretApp.familySearchComparisonDebugMessage)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var familySearchComparisonClipboardText: String {
        FamilySearchComparisonClipboardFormatter.text(
            debugMessage: juuretApp.familySearchComparisonDebugMessage,
            debugLines: juuretApp.familySearchComparisonDebugLines,
            rows: juuretApp.familySearchComparisonResult?.rows ?? [],
            status: juuretApp.familySearchComparisonStatus(for:)
        )
    }

    private func familySearchComparisonTable(rows: [FamilyComparisonResult.Match]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                comparisonHeader("Child name")
                comparisonHeader("Juuret")
                comparisonHeader("HisKi")
                comparisonHeader("FamilySearch")
                comparisonHeader("Status")
            }

            Divider()
                .gridCellColumns(5)

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    comparisonCell(displayName(for: row))
                    comparisonCell(sourceCell(row.juuretKalvialla))
                    comparisonCell(sourceCell(row.hiski))
                    comparisonCell(sourceCell(row.familySearch))
                    comparisonCell(juuretApp.familySearchComparisonStatus(for: row))
                }
            }
        }
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
    }

    private func comparisonHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .foregroundStyle(.primary)
    }

    private func comparisonCell(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func displayName(for row: FamilyComparisonResult.Match) -> String {
        row.juuretKalvialla?.rawName
            ?? row.hiski?.rawName
            ?? row.familySearch?.rawName
            ?? "(unknown)"
    }

    private func sourceCell(_ candidate: PersonCandidate?) -> String {
        guard let candidate else {
            return "No"
        }

        var parts = ["Yes"]
        if let familySearchId = candidate.familySearchId {
            parts.append("<\(familySearchId)>")
        }
        if let birthDate = candidate.birthDate {
            parts.append(formatComparisonDate(birthDate))
        }
        if let deathDate = candidate.deathDate {
            parts.append("d. \(formatComparisonDate(deathDate))")
        }
        return parts.joined(separator: "\n")
    }

    private func formatComparisonDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "dd MMM yyyy"
        return formatter.string(from: date)
    }
    
    private func noteDefinitionsSection() -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(family.noteDefinitions.keys.sorted()), id: \.self) { key in
                if let text = family.noteDefinitions[key] {
                    Text("\(key) \(text)")
                        .applyFamilyLineStyle()
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = text
        #endif
    }
    
    // MARK: - Family Header
    
    private var familyHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Family ID
            Text(family.familyId)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
            
            // Page references
            if !family.pageReferences.isEmpty {
                Text("Pages \(family.pageReferences.joined(separator: ", "))")
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(.primary)
            }
        }
    }
    
    // MARK: - Parent Lines
    
    private func parentLines(couple: Couple) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Father line
            PersonLineView(
                person: couple.husband,
                network: juuretApp.familyNetworkWorkflow?.getFamilyNetwork(),
                onNameClick: { person in
                    generateCitationFor(person)
                },
                onDateClick: { date, eventType in
                    generateHiskiFor(person: couple.husband, date: date, eventType: eventType)
                },
                onSpouseDateClick: { _, _, _ in },
                onFamilyIdClick: { familyId in
                    juuretApp.navigateToFamily(familyId, updateHistory: false)
                }
            )
            
            // Mother line
            PersonLineView(
                person: couple.wife,
                network: juuretApp.familyNetworkWorkflow?.getFamilyNetwork(),
                onNameClick: { person in
                    generateCitationFor(person)
                },
                onDateClick: { date, eventType in
                    generateHiskiFor(person: couple.wife, date: date, eventType: eventType)
                },
                onSpouseDateClick: { _, _, _ in },
                onFamilyIdClick: { familyId in
                    juuretApp.navigateToFamily(familyId, updateHistory: false)
                }
            )
        }
    }
    
    // MARK: - Marriage Line
    
    private func marriageLine(date: String, couple: Couple) -> some View {
        HStack(spacing: 4) {
            Text("∞")
                .applyFamilyLineStyle()
            
            Button(action: {
                Task {
                    let result = await juuretApp.processHiskiQuery(
                        for: couple.husband,
                        eventType: EventType.marriage,
                        familyId: family.familyId,
                        explicitDate: date,
                        spouseName: couple.wife.name
                    )
                    onShowHiski(result)
                }
            }) {
                Text(date)
                    .applyFamilyLineStyle()
                    .foregroundColor(Color(hex: "0066cc"))
            }
            .buttonStyle(.plain)
            
            Text(".")
                .applyFamilyLineStyle()
        }
    }
    
    // MARK: - Children Section
    
    private func childrenSection(children: [Person]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // "Lapset" header
            Text("Lapset")
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
                .padding(.bottom, 2)
            
            // Child lines
            ForEach(children) { child in
                PersonLineView(
                    person: child,
                    network: juuretApp.familyNetworkWorkflow?.getFamilyNetwork(),
                    onNameClick: { person in
                        generateCitationFor(person)
                    },
                    onDateClick: { date, eventType in
                        generateHiskiFor(person: child, date: date, eventType: eventType)
                    },
                    onSpouseDateClick: { date, eventType, spouseData in
                        let spousePerson = Person(name: spouseData.fullName, birthDate: spouseData.birthDate, deathDate: spouseData.deathDate, noteMarkers: [])
                        generateHiskiFor(person: spousePerson, date: date, eventType: eventType)
                    },
                    onFamilyIdClick: { familyId in
                        juuretApp.navigateToFamily(familyId, updateHistory: false)
                    }
                )
            }
        }
    }
    
    // MARK: - Additional Spouses
    
    private func additionalSpouses() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(family.couples.dropFirst().enumerated()), id: \.offset) { index, couple in
                additionalSpouseSection(couple: couple, spouseNumber: index + 2)
            }
        }
    }
    
    private func additionalSpouseSection(couple: Couple, spouseNumber: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Spouse header (II puoliso, III puoliso, etc.)
            Text("\(romanNumeral(spouseNumber)) puoliso")
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
                .padding(.top, 4)
            
            // Determine which person is the new spouse
            let previousCouple = family.couples[spouseNumber - 2]
            let isHusbandContinuing = couple.husband.name == previousCouple.husband.name &&
                                      couple.husband.birthDate == previousCouple.husband.birthDate
            
            let additionalSpouse = isHusbandContinuing ? couple.wife : couple.husband
            
            // Additional spouse line
            PersonLineView(
                person: additionalSpouse,
                network: juuretApp.familyNetworkWorkflow?.getFamilyNetwork(),
                onNameClick: { person in
                    generateCitationFor(person)
                },
                onDateClick: { date, eventType in
                    generateHiskiFor(person: additionalSpouse, date: date, eventType: eventType)
                },
                onSpouseDateClick: { _, _, _ in },
                onFamilyIdClick: { familyId in
                    juuretApp.navigateToFamily(familyId, updateHistory: false)
                }
            )
            
            // Marriage date for this couple
            if let marriageDate = couple.fullMarriageDate ?? couple.marriageDate {
                marriageLine(date: marriageDate, couple: couple)
                    .padding(.top, 2)
            }
            
            // Children with this spouse
            if !couple.children.isEmpty {
                childrenSection(children: couple.children)
                    .padding(.top, 4)
            }
            
            // Children died in infancy for this couple
            if let died = couple.childrenDiedInfancy, died > 0 {
                Text("Lapsena kuollut \(died).")
                    .applyFamilyLineStyle()
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.top, 4)
            }
        }
    }
    
    // MARK: - Notes Section
    
    private func notesSection() -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(family.notes.enumerated()), id: \.offset) { _, note in
                Text(note)
                    .applyFamilyLineStyle()
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func generateCitationFor(_ person: Person) {
        Task {
            let citation = await juuretApp.generateCitation(for: person, in: family)
            onShowCitation(citation)
        }
    }
    
    private func generateHiskiFor(person: Person, date: String, eventType: EventType) {
        Task {
            let result = await juuretApp.processHiskiQuery(
                for: person,
                eventType: eventType,
                familyId: family.familyId,
                explicitDate: date
            )
            onShowHiski(result)
        }
    }
    private func romanNumeral(_ number: Int) -> String {
        switch number {
        case 1: return "I"
        case 2: return "II"
        case 3: return "III"
        case 4: return "IV"
        case 5: return "V"
        case 6: return "VI"
        case 7: return "VII"
        case 8: return "VIII"
        case 9: return "IX"
        case 10: return "X"
        default: return "\(number)"
        }
    }
}

enum FamilySearchComparisonClipboardFormatter {
    static func text(
        debugMessage: String,
        debugLines: [String],
        rows: [FamilyComparisonResult.Match],
        status: (FamilyComparisonResult.Match) -> String
    ) -> String {
        var lines = [
            "Juuret / HisKi / FamilySearch Children Comparison",
            debugMessage.isEmpty ? "Comparison not triggered" : debugMessage
        ]

        if !debugLines.isEmpty {
            lines.append("")
            lines.append("Debug")
            lines.append(contentsOf: debugLines)
        }

        lines.append("")
        lines.append(["Child name", "Juuret", "HisKi", "FamilySearch", "Status"].joined(separator: "\t"))

        if rows.isEmpty {
            lines.append("(no rows)\t\t\t\t\(debugMessage.isEmpty ? "Comparison not triggered" : debugMessage)")
        } else {
            lines.append(contentsOf: rows.map { row in
                [
                    displayName(for: row),
                    sourceCell(row.juuretKalvialla),
                    sourceCell(row.hiski),
                    sourceCell(row.familySearch),
                    status(row)
                ].map(sanitizeCell).joined(separator: "\t")
            })
        }

        return lines.joined(separator: "\n")
    }

    private static func displayName(for row: FamilyComparisonResult.Match) -> String {
        row.juuretKalvialla?.rawName
            ?? row.hiski?.rawName
            ?? row.familySearch?.rawName
            ?? "(unknown)"
    }

    private static func sourceCell(_ candidate: PersonCandidate?) -> String {
        guard let candidate else {
            return "No"
        }

        var parts = ["Yes"]
        if let familySearchId = candidate.familySearchId {
            parts.append("<\(familySearchId)>")
        }
        if let birthDate = candidate.birthDate {
            parts.append(formatComparisonDate(birthDate))
        }
        if let deathDate = candidate.deathDate {
            parts.append("d. \(formatComparisonDate(deathDate))")
        }
        return parts.joined(separator: " | ")
    }

    private static func sanitizeCell(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " | ")
    }

    private static func formatComparisonDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "dd MMM yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - View Modifiers

extension View {
    /// Apply consistent family line styling
    func applyFamilyLineStyle() -> some View {
        self
            .font(.system(size: 16, design: .monospaced))
            .lineSpacing(1.3)
    }
}

// MARK: - Preview

#Preview {
    let sampleFamily = Family.sampleFamily()
    
    return FamilyContentView(
        family: sampleFamily,
        onShowCitation: { citation in
            print("Citation: \(citation)")
        },
        onShowHiski: { hiski in
            print("Hiski: \(hiski)")
        }
    )
    .environment(JuuretApp())
}
