import Foundation
import FoundationModels

@Generable
struct GeneratedJuuretFamily: Codable {
    @Guide(description: "heading id")
    var familyId: String
    @Guide(description: "heading pages")
    var pageReferences: [String]
    @Guide(description: "parent couples only")
    var couples: [GeneratedJuuretCouple]
    var notes: [String]

    func toFamily() -> Family {
        Family(
            familyId: familyId,
            pageReferences: pageReferences,
            couples: couples.map { $0.toCouple() },
            notes: notes,
            noteDefinitions: [:]
        )
    }
}

@Generable
struct GeneratedJuuretCouple: Codable {
    @Guide(description: "father")
    var husband: GeneratedJuuretPerson
    @Guide(description: "mother")
    var wife: GeneratedJuuretPerson
    var marriageDate: String?
    @Guide(description: "Lapset rows")
    var children: [GeneratedJuuretPerson]
    var childrenDiedInfancy: Int?
    var coupleNotes: [String]

    func toCouple() -> Couple {
        Couple(
            husband: husband.toPerson(),
            wife: wife.toPerson(),
            marriageDate: marriageDate,
            fullMarriageDate: nil,
            children: children.map { $0.toPerson() },
            childrenDiedInfancy: childrenDiedInfancy,
            coupleNotes: coupleNotes
        )
    }
}

@Generable
struct GeneratedJuuretPerson: Codable {
    @Guide(description: "given names")
    var name: String
    @Guide(description: "patronymic")
    var patronymic: String?
    var birthDate: String?
    var deathDate: String?
    var familySearchId: String?
    var asChild: String?
    var marriageDate: String?
    var spouse: String?
    var spouseFamilySearchId: String?
    var asParent: String?
    var notes: [String]

    func toPerson() -> Person {
        Person(
            name: name,
            patronymic: patronymic.nilIfBlank,
            birthDate: birthDate.nilIfBlank,
            deathDate: deathDate.nilIfBlank,
            marriageDate: marriageDate.nilIfBlank,
            fullMarriageDate: nil,
            spouse: spouse.nilIfBlank,
            asChild: asChild.nilIfBlank,
            asParent: asParent.nilIfBlank,
            familySearchId: familySearchId.nilIfBlank,
            spouseFamilySearchId: spouseFamilySearchId.nilIfBlank,
            noteMarkers: notes
        )
    }
}

@main
struct JuuretFoundationModelsDemo {
    static func main() async {
        do {
            let arguments = try Arguments.parse(CommandLine.arguments.dropFirst())

            if arguments.printSchema {
                print(GeneratedJuuretFamily.generationSchema.debugDescription)
                return
            }

            let familyText = try arguments.familyText()
            if arguments.printInput {
                print(familyText)
                return
            }

            let model = SystemLanguageModel.default

            guard model.isAvailable else {
                print("System language model is unavailable: \(model.availability)")
                return
            }

            let session = LanguageModelSession(
                model: model,
                instructions: """
                Parse Juuret family text. Preserve names, patronymics, dates, IDs, and references exactly.
                The heading before comma/pages is familyId. Heading page text is pageReferences.
                First starred adult is husband, second starred adult is wife, following infinity is their marriageDate.
                Lines under Lapset are children, not new couples.
                On child rows, text after infinity is the child's marriageDate, spouse, spouseFamilySearchId, and asParent.
                Do not create couples from married child rows.
                Never infer patronymics or surnames. If a child row has no patronymic printed, patronymic is null.
                Do not copy spouse names, destination families, death dates, or notes into patronymic.
                Do not use death dates as marriage dates, spouse names, IDs, asChild, or asParent.
                Angle-bracket IDs are FamilySearch IDs. Brace references are asChild. Missing optionals are null.
                """
            )

            let prompt = """
            Parse this family:

            \(familyText)
            """

            let response = try await session.respond(
                to: prompt,
                generating: GeneratedJuuretFamily.self,
                options: GenerationOptions(temperature: 0.0, maximumResponseTokens: 2048)
            )

            let generated = response.content
            let family = generated.toFamily()

            try printResult(generated: generated, family: family)
            printKorpi6Checks(family)
        } catch {
            fputs("Error: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func printResult(generated: GeneratedJuuretFamily, family: Family) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        let data = try encoder.encode(generated)
        print(String(decoding: data, as: UTF8.self))

        print("")
        print("Converted Family summary")
        print("familyId: \(family.familyId)")
        print("pages: \(family.pageReferenceString)")
        print("couples: \(family.couples.count)")
        print("children: \(family.couples.reduce(0) { $0 + $1.children.count })")

        for (index, couple) in family.couples.enumerated() {
            print("")
            print("Couple \(index + 1): \(couple.husband.displayName) + \(couple.wife.displayName)")
            if let marriageDate = couple.marriageDate {
                print("marriage: \(marriageDate)")
            }
            for child in couple.children {
                let id = child.familySearchId.map { " <\($0)>" } ?? ""
                let birth = child.birthDate.map { " * \($0)" } ?? ""
                let spouse = child.spouse.map { " spouse: \($0)" } ?? ""
                let asParent = child.asParent.map { " -> \($0)" } ?? ""
                print("- \(child.displayName)\(id)\(birth)\(spouse)\(asParent)")
            }
            if let died = couple.childrenDiedInfancy {
                print("childrenDiedInfancy: \(died)")
            }
        }
    }

    private static func printKorpi6Checks(_ family: Family) {
        guard family.familyId == "KORPI 6" || family.couples.first?.husband.familySearchId == "LCJZ-BH3" else {
            return
        }

        let checks: [(String, Bool)] = [
            ("familyId is KORPI 6", family.familyId == "KORPI 6"),
            ("one parent couple", family.couples.count == 1),
            ("ten listed children", family.couples.first?.children.count == 10),
            ("childrenDiedInfancy is 4", family.couples.first?.childrenDiedInfancy == 4),
            ("Maria spouse parsed", family.couples.first?.children.first(where: { $0.name == "Maria" })?.spouse == "Elias Iso-Peitso"),
            ("child patronymics are not inferred", family.couples.first?.children.allSatisfy { $0.patronymic == nil } == true),
            ("unmarried Erik has no spouse", family.couples.first?.children.first(where: { $0.name == "Erik" })?.spouse == nil),
            ("Abraham has no fabricated FamilySearch ID", family.couples.first?.children.first(where: { $0.name == "Abraham" })?.familySearchId == nil)
        ]

        print("")
        print("KORPI 6 checks")
        for (label, passed) in checks {
            print("\(passed ? "PASS" : "FAIL") \(label)")
        }
    }
}

struct Arguments {
    var rootsFile: String?
    var familyId: String = "KORPI 6"
    var printSchema = false
    var printInput = false

    static func parse<S: Sequence>(_ rawArguments: S) throws -> Arguments where S.Element == String {
        var parsed = Arguments()
        var iterator = rawArguments.makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "--roots-file":
                parsed.rootsFile = try requireValue(after: argument, from: &iterator)
            case "--family-id":
                parsed.familyId = try requireValue(after: argument, from: &iterator)
            case "--print-schema":
                parsed.printSchema = true
            case "--print-input":
                parsed.printInput = true
            case "--help", "-h":
                printUsage()
                exit(0)
            default:
                throw PrototypeError.invalidArgument(argument)
            }
        }

        return parsed
    }

    func familyText() throws -> String {
        guard let rootsFile else {
            return SampleFamilies.korpi6
        }

        let text = try String(contentsOfFile: NSString(string: rootsFile).expandingTildeInPath, encoding: .utf8)
        return try extractFamily(familyId: familyId, from: text)
    }

    private static func requireValue<I: IteratorProtocol>(after argument: String, from iterator: inout I) throws -> String where I.Element == String {
        guard let value = iterator.next(), !value.hasPrefix("--") else {
            throw PrototypeError.missingValue(argument)
        }
        return value
    }

    private static func printUsage() {
        print("""
        Usage:
          run.sh [--print-schema]
          run.sh [--print-input] [--roots-file PATH] [--family-id "KORPI 6"]
          run.sh [--roots-file PATH] [--family-id "KORPI 6"]
        """)
    }
}

enum PrototypeError: Error, CustomStringConvertible {
    case invalidArgument(String)
    case missingValue(String)
    case familyNotFound(String)

    var description: String {
        switch self {
        case .invalidArgument(let argument):
            return "invalid argument: \(argument)"
        case .missingValue(let argument):
            return "missing value after \(argument)"
        case .familyNotFound(let familyId):
            return "family not found: \(familyId)"
        }
    }
}

func extractFamily(familyId: String, from rootsText: String) throws -> String {
    let escaped = NSRegularExpression.escapedPattern(for: familyId)
    let headingPattern = #"(?m)^\#(escaped)(?:,|\s+pages?|\s+page|\b).*"#

    guard let headingRange = rootsText.range(of: headingPattern, options: .regularExpression) else {
        throw PrototypeError.familyNotFound(familyId)
    }

    let familyStart = headingRange.lowerBound
    let afterHeading = rootsText[headingRange.upperBound...]
    if let following = afterHeading.range(
        of: #"(?m)^[A-ZÅÄÖ][A-ZÅÄÖa-zåäö\- ]+\s+\d+[A-Z]?(?:,|\s+pages?|\s+page).*"#,
        options: .regularExpression
    ) {
        return String(rootsText[familyStart..<following.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    return String(rootsText[familyStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
}

enum SampleFamilies {
    static let korpi6 = """
    KORPI 6, pages 105-106
    ★ 09.09.1727\tMatti Erikinp. <LCJZ-BH3> {Korpi 5}                            † 22.08.1812
    ★ 05.09.1731\tBrita Matint. <KCJW-98X> {Sikala 5}, synt. Hanhisalo            † 11.07.1769
    ∞ 14.10.1750.
    Lapset
    ★ 10.02.1752\tMaria <KJJH-2R9>       \t∞ 73 Elias Iso-Peitso <GMG6-NCZ>        Iso-Peitso III 2
    ★ 01.02.1753\tKaarin <LJKQ-PLT>                            Kuoli Rimpilässä   † 17.04.1795
    ★ 14.03.1754\tLiisa <LJKQ-PGQ>        ∞ 80 Juho Vapola <LHVG-XP4>             Loht. Vapola
    ★ 31.03.1755\tAnna <M8ZT-J2S>\t        ∞ 03 1. Antti Hassinen <GMG6-GJ7>       Laxo 4
    ★ 20.07.1756\tErik <GMVS-VB1>
    ★ 18.10.1757\tMargeta <LWVL-7BK>
    ★ 27.01.1759\tMagdalena <L4ZM-CRT>    ∞ 78 Antti Korvela <L4ZM-PWD>           Korvela 3
    ★ 24.06.1760\tMatti <LJKQ-LBQ>        ∞ 89 1. Anna Videnoja <G9PV-58P>\t    Rimpilä 7
    ★ 03.04.1762\tAntti <LZJ2-YG4>
    ★ 08.01.1764    Abraham\t                ∞ 87 Anna Sikala\t                    Jänesniemi 5
    Lapsena kuollut 4.
    """
}

extension Optional where Wrapped == String {
    var nilIfBlank: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value.lowercased() != "null" else {
            return nil
        }
        return value
    }
}
