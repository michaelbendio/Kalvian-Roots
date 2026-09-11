import Foundation

public struct Person: Hashable, Sendable, Codable, Identifiable {
  public var name: String
  public var patronymic: String?
  public var birthDate: String?
  public var deathDate: String?
  public var marriageDate: String?
  public var fullMarriageDate: String?
  public var spouse: String?
  public var asChild: String?
  public var asParent: String?
  public var familySearchId: String?
  public var spouseFamilySearchId: String?
  public var noteMarkers: [String]
  public var fatherName: String?
  public var motherName: String?
  public var spouseBirthDate: String?
  public var spouseParentsFamilyId: String?

  public init(
    name: String,
    patronymic: String? = nil,
    birthDate: String? = nil,
    deathDate: String? = nil,
    marriageDate: String? = nil,
    fullMarriageDate: String? = nil,
    spouse: String? = nil,
    asChild: String? = nil,
    asParent: String? = nil,
    familySearchId: String? = nil,
    spouseFamilySearchId: String? = nil,
    noteMarkers: [String] = [],
    fatherName: String? = nil,
    motherName: String? = nil,
    spouseBirthDate: String? = nil,
    spouseParentsFamilyId: String? = nil
  ) {
    self.name = name
    self.patronymic = patronymic
    self.birthDate = birthDate
    self.deathDate = deathDate
    self.marriageDate = marriageDate
    self.fullMarriageDate = fullMarriageDate
    self.spouse = spouse
    self.asChild = asChild
    self.asParent = asParent
    self.familySearchId = familySearchId
    self.spouseFamilySearchId = spouseFamilySearchId
    self.noteMarkers = noteMarkers
    self.fatherName = fatherName
    self.motherName = motherName
    self.spouseBirthDate = spouseBirthDate
    self.spouseParentsFamilyId = spouseParentsFamilyId
  }

  public var displayName: String {
    patronymic.map { "\(name) \($0)" } ?? name
  }

  public var id: String {
    "\(name)-\(patronymic ?? "")-\(birthDate ?? "")"
  }

  public var bestMarriageDate: String? { fullMarriageDate ?? marriageDate }
  public var isMarried: Bool { spouse != nil || marriageDate != nil || fullMarriageDate != nil }
  public var needsCrossReferenceResolution: Bool { asChild != nil || asParent != nil || spouse != nil }
  public var hasParentInfo: Bool { fatherName != nil || motherName != nil }

  public func getFormattedDate(_ date: String?) -> String? { date }

  public func validateData() -> [String] {
    var warnings: [String] = []
    if name.isEmpty { warnings.append("Person name is required") }
    if let birthDate, !Self.isValidDateFormat(birthDate) {
      warnings.append("Unusual birth date format: \(birthDate)")
    }
    if let deathDate, !Self.isValidDateFormat(deathDate) {
      warnings.append("Unusual death date format: \(deathDate)")
    }
    return warnings
  }

  public mutating func enhanceWithSpouseData(
    birthDate: String? = nil,
    parentsFamilyId: String? = nil
  ) {
    if let birthDate { spouseBirthDate = birthDate }
    if let parentsFamilyId { spouseParentsFamilyId = parentsFamilyId }
  }

  public mutating func enhanceWithParentNames(father: String? = nil, mother: String? = nil) {
    if let father { fatherName = father }
    if let mother { motherName = mother }
  }

  public func withHiskiParentNames(father: String?, mother: String?) -> Person {
    var copy = self
    if copy.fatherName?.isEmpty != false { copy.fatherName = father }
    if copy.motherName?.isEmpty != false { copy.motherName = mother }
    return copy
  }

  private static func isValidDateFormat(_ date: String) -> Bool {
    date.range(of: #"^\d{1,2}\.\d{1,2}\.\d{4}$"#, options: .regularExpression) != nil
  }
}

public struct Couple: Hashable, Sendable, Codable {
  public var husband: Person
  public var wife: Person
  public var marriageDate: String?
  public var fullMarriageDate: String?
  public var children: [Person]
  public var childrenDiedInfancy: Int?
  public var coupleNotes: [String]

  public init(
    husband: Person,
    wife: Person,
    marriageDate: String? = nil,
    fullMarriageDate: String? = nil,
    children: [Person] = [],
    childrenDiedInfancy: Int? = nil,
    coupleNotes: [String] = []
  ) {
    self.husband = husband
    self.wife = wife
    self.marriageDate = marriageDate
    self.fullMarriageDate = fullMarriageDate
    self.children = children
    self.childrenDiedInfancy = childrenDiedInfancy
    self.coupleNotes = coupleNotes
  }
}

public struct Family: Hashable, Sendable, Codable {
  public var familyId: String
  public var pageReferences: [String]
  public var couples: [Couple]
  public var notes: [String]
  public var noteDefinitions: [String: String]
  public var editorialSource: JuuretEditorialSource?

  public init(
    familyId: String,
    pageReferences: [String],
    husband: Person,
    wife: Person,
    marriageDate: String? = nil,
    children: [Person] = [],
    childrenDiedInfancy: Int? = nil,
    notes: [String] = [],
    noteDefinitions: [String: String] = [:],
    editorialSource: JuuretEditorialSource? = nil
  ) {
    self.init(
      familyId: familyId,
      pageReferences: pageReferences,
      couples: [Couple(
        husband: husband,
        wife: wife,
        marriageDate: marriageDate,
        children: children,
        childrenDiedInfancy: childrenDiedInfancy
      )],
      notes: notes,
      noteDefinitions: noteDefinitions,
      editorialSource: editorialSource
    )
  }

  public init(
    familyId: String,
    pageReferences: [String],
    couples: [Couple],
    notes: [String] = [],
    noteDefinitions: [String: String] = [:],
    editorialSource: JuuretEditorialSource? = nil
  ) {
    self.familyId = familyId
    self.pageReferences = pageReferences
    self.couples = couples
    self.notes = notes
    self.noteDefinitions = noteDefinitions
    self.editorialSource = editorialSource
  }

  public var primaryCouple: Couple? { couples.first }
  public var allParents: [Person] { couples.flatMap { [$0.husband, $0.wife] } }
  public var marriedChildren: [Person] { couples.flatMap(\.children).filter(\.isMarried) }
  public var totalChildrenDiedInfancy: Int { couples.compactMap(\.childrenDiedInfancy).reduce(0, +) }
  public var pageReferenceString: String {
    pageReferences.count == 1
      ? "page \(pageReferences[0])"
      : "pages \(pageReferences.joined(separator: ", "))"
  }
  public var isValid: Bool { !familyId.isEmpty && !pageReferences.isEmpty && !couples.isEmpty }

  public func findPerson(named name: String) -> Person? {
    for couple in couples {
      if couple.husband.name.caseInsensitiveCompare(name) == .orderedSame { return couple.husband }
      if couple.wife.name.caseInsensitiveCompare(name) == .orderedSame { return couple.wife }
      if let child = couple.children.first(where: {
        $0.name.caseInsensitiveCompare(name) == .orderedSame
      }) { return child }
    }
    return nil
  }

  public var allPersons: [Person] {
    var names: Set<String> = []
    var result: [Person] = []
    for couple in couples {
      for person in [couple.husband, couple.wife] + couple.children where names.insert(person.name).inserted {
        result.append(person)
      }
    }
    return result
  }

  public func findCoupleForChild(_ childName: String) -> Couple? {
    couples.first { couple in
      couple.children.contains { $0.name.caseInsensitiveCompare(childName) == .orderedSame }
    }
  }

  public func getParentNames(for child: Person) -> (father: String, mother: String?)? {
    findCoupleForChild(child.name).map { ($0.husband.displayName, $0.wife.displayName) }
  }

  public func validateStructure() -> [String] {
    var warnings: [String] = []
    if familyId.isEmpty { warnings.append("Family ID is required") }
    if pageReferences.isEmpty { warnings.append("Page references are required") }
    if couples.isEmpty { warnings.append("At least one couple is required") }
    for (index, couple) in couples.enumerated() {
      if couple.husband.name.isEmpty { warnings.append("Couple \(index + 1): Husband name is required") }
      if couple.wife.name.isEmpty { warnings.append("Couple \(index + 1): Wife name is required") }
      let names = couple.children.map { $0.name.lowercased() }
      if names.count != Set(names).count {
        warnings.append("Couple \(index + 1): Duplicate child names found")
      }
    }
    return warnings
  }
}
