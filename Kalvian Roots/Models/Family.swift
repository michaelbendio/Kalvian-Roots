import KalvianRootsCore

typealias Couple = KalvianRootsCore.Couple
typealias Family = KalvianRootsCore.Family

extension Family {
    static func sampleFamily() -> Family {
        Family(
            familyId: "SAMPLE 1",
            pageReferences: ["105", "106"],
            husband: Person(
                name: "Matti",
                patronymic: "Erikinp.",
                birthDate: "15.03.1723",
                deathDate: "12.11.1798"
            ),
            wife: Person(
                name: "Brita",
                patronymic: "Jaakont.",
                birthDate: "22.08.1731",
                deathDate: "05.07.1805"
            ),
            marriageDate: "1750",
            children: [
                Person(
                    name: "Maria",
                    patronymic: "Matint.",
                    birthDate: "18.05.1751",
                    marriageDate: "73",
                    spouse: "Juho Juhonp.",
                    asParent: "KORPI 8"
                ),
                Person(name: "Erik", patronymic: "Matinp.", birthDate: "03.09.1753")
            ]
        )
    }
}
