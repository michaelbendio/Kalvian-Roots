import Foundation

struct FamilySearchPersonSummary: Codable, Equatable, Hashable {
    var id: String?
    var name: String
    var birthDate: String?
    var birthPlace: String?
    var deathDate: String?
    var deathPlace: String?
    var lifeSpan: String?
}

struct FamilySearchMarriageSummary: Codable, Equatable, Hashable {
    var date: String?
    var place: String?
}

struct FamilySearchChild: Codable, Equatable, Hashable {
    var id: String
    var name: String
    var birthDate: String?
    var birthPlace: String?
    var deathDate: String?
    var deathPlace: String?
    var lifeSpan: String?
}

struct FamilySearchFamilyExtraction: Codable, Equatable, Hashable {
    var sourcePersonId: String
    var focusPerson: FamilySearchPersonSummary?
    var spouse: FamilySearchPersonSummary?
    var marriage: FamilySearchMarriageSummary?
    var children: [FamilySearchChild]
}

enum FamilySearchDOMService {

    static let detailsBaseURL = "https://www.familysearch.org/en/tree/person/details/"

    static func detailsURL(for personId: String) -> String {
        detailsBaseURL + personId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func makePersonCandidates(
        from children: [FamilySearchChild],
        nameManager: NameEquivalenceManager,
        dateParser: (String?) -> Date?
    ) -> [PersonCandidate] {
        children.map { child in
            PersonCandidate(
                name: child.name,
                birthDate: dateParser(child.birthDate),
                deathDate: dateParser(child.deathDate),
                source: .familySearch,
                nameManager: nameManager,
                familySearchId: child.id,
                hiskiCitation: nil
            )
        }
    }

    static func makeAtlasExtractorScript(callbackURL: String? = nil) -> String {
        let callbackLine: String
        if let callbackURL {
            callbackLine = "const KALVIAN_ROOTS_CALLBACK_URL = '\(escapeJavaScript(callbackURL))';"
        } else {
            callbackLine = "const KALVIAN_ROOTS_CALLBACK_URL = null;"
        }

        return """
        (function () {
            \(callbackLine)

            function clean(text) {
                return (text || '').replace(/\\s+/g, ' ').trim();
            }

            function sleep(ms) {
                return new Promise(resolve => setTimeout(resolve, ms));
            }

            let extractionWindow = null;

            function extractionDocument() {
                if (extractionWindow && !extractionWindow.closed) {
                    return extractionWindow.document;
                }
                return document;
            }

            function personIdFromURL() {
                const match = extractionDocument().location.pathname.match(/\\/tree\\/person\\/details\\/([A-Z0-9-]+)/i);
                return match ? match[1].toUpperCase() : null;
            }

            function findHeading(label) {
                return Array.from(extractionDocument().querySelectorAll('h1,h2,h3,h4,h5,h6,a,button,span,div'))
                    .find(element => clean(element.textContent) === label);
            }

            function sectionTextAfterLabel(label) {
                const anchor = findHeading(label);
                const root = anchor && (anchor.closest('section') || anchor.closest('[data-testid]') || anchor.parentElement);
                return root ? clean(root.innerText) : '';
            }

            function extractVital(label) {
                const text = sectionTextAfterLabel(label);
                const lines = text.split(/\\n| {2,}/).map(clean).filter(Boolean);
                const index = lines.findIndex(line => line === label);
                const values = index >= 0 ? lines.slice(index + 1) : lines;
                return {
                    date: values[0] || null,
                    place: values[1] || null
                };
            }

            function extractPersonSummary() {
                const name = clean((extractionDocument().querySelector('h1') || {}).textContent);
                const birth = extractVital('Birth');
                const death = extractVital('Death');
                return {
                    id: personIdFromURL(),
                    name,
                    birthDate: birth.date,
                    birthPlace: birth.place,
                    deathDate: death.date,
                    deathPlace: death.place,
                    lifeSpan: null
                };
            }

            function familyMembersSection() {
                const heading = findHeading('Family Members');
                return heading && (heading.closest('section') || heading.closest('div[all]') || heading.parentElement);
            }

            function extractMarriage() {
                const text = clean((familyMembersSection() || {}).innerText || '');
                const marriageMatch = text.match(/Marriage\\s+([^\\n]+?)(?:\\s{2,}|\\n|Children \\(|$)/i);
                if (!marriageMatch) return { date: null, place: null };

                const parts = clean(marriageMatch[1]).split(/,\\s*/);
                return {
                    date: parts.shift() || null,
                    place: parts.join(', ') || null
                };
            }

            function childCards() {
                const section = familyMembersSection();
                if (!section) return [];

                const text = section.innerText || '';
                const childrenStart = text.search(/Children \\(\\d+\\)|\\bChildren\\b/i);
                if (childrenStart >= 0) {
                    let end = text.indexOf('ADD CHILD', childrenStart);
                    if (end === -1) end = text.indexOf('Parents and Siblings', childrenStart);
                    if (end === -1) end = text.length;

                    const lines = text.slice(childrenStart, end)
                        .split('\\n')
                        .map(clean)
                        .filter(Boolean);
                    const children = [];
                    let i = /^Children( \\(\\d+\\))?$/i.test(lines[0] || '') ? 1 : 0;

                    while (i < lines.length) {
                        const name = lines[i] || '';
                        const sex = lines[i + 1] || '';
                        const lifeSpan = lines[i + 2] || '';
                        const id = lines.slice(i + 1, i + 6).find(line => /^[A-Z0-9]{4}-[A-Z0-9]{3,}$/i.test(line)) || '';

                        if (/^(Male|Female|Unknown)$/i.test(sex) && id) {
                            children.push({
                                id: id.toUpperCase(),
                                name,
                                birthDate: null,
                                birthPlace: null,
                                deathDate: null,
                                deathPlace: null,
                                lifeSpan: /\\b\\d{4}\\b/.test(lifeSpan) ? lifeSpan : null
                            });
                            i += 5;
                        } else {
                            i += 1;
                        }
                    }

                    if (children.length > 0) {
                        return children;
                    }
                }

                const childrenHeading = Array.from(section.querySelectorAll('h1,h2,h3,h4,h5,h6,span,div'))
                    .find(element => /^Children( \\(\\d+\\))?$/i.test(clean(element.textContent)));
                const childrenRoot = childrenHeading && (childrenHeading.closest('section') || childrenHeading.parentElement);
                const linkRoot = childrenRoot || section;

                return Array.from(linkRoot.querySelectorAll('a[href*="/tree/person/details/"]'))
                    .map(anchor => {
                        const href = anchor.getAttribute('href') || '';
                        const match = href.match(/\\/tree\\/person\\/details\\/([A-Z0-9-]+)/i);
                        if (!match) return null;

                        const card = anchor.closest('li,article,div') || anchor;
                        const lines = (card.innerText || '').split('\\n').map(clean).filter(Boolean);
                        const name = clean(anchor.textContent) || lines[0] || '';
                        const lifeSpan = lines.find(line => /\\b\\d{4}\\b/.test(line)) || null;

                        return {
                            id: match[1].toUpperCase(),
                            name,
                            birthDate: null,
                            birthPlace: null,
                            deathDate: null,
                            deathPlace: null,
                            lifeSpan
                        };
                    })
                    .filter(Boolean)
                    .filter((child, index, all) => all.findIndex(other => other.id === child.id) === index);
            }

            async function waitForDetailsPage(expectedId) {
                for (let attempt = 0; attempt < 80; attempt += 1) {
                    if (personIdFromURL() === expectedId && extractionDocument().readyState === 'complete') {
                        await sleep(500);
                        return;
                    }
                    await sleep(250);
                }
                throw new Error('Timed out waiting for FamilySearch details page ' + expectedId);
            }

            async function visitPerson(personId) {
                const target = '\(detailsBaseURL)' + personId;
                if (!extractionWindow || extractionWindow.closed) {
                    extractionWindow = window.open(target, 'kalvianRootsFamilySearchExtractor', 'popup,width=1200,height=900');
                } else if (personIdFromURL() !== personId) {
                    extractionWindow.location.assign(target);
                }
                await waitForDetailsPage(personId);
                return extractPersonSummary();
            }

            async function postResult(result) {
                if (!KALVIAN_ROOTS_CALLBACK_URL) return;

                await fetch(KALVIAN_ROOTS_CALLBACK_URL, {
                    method: 'POST',
                    mode: 'cors',
                    credentials: 'include',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(result)
                });
            }

            window.extractFamilySearchChildren = async function extractFamilySearchChildren(personId) {
                const normalizedPersonId = clean(personId).toUpperCase();
                const focusPerson = await visitPerson(normalizedPersonId);
                const marriage = extractMarriage();
                const summaries = childCards();

                let spouse = null;
                const familyText = clean((familyMembersSection() || {}).innerText || '');
                const spouseLink = Array.from(extractionDocument().querySelectorAll('a[href*="/tree/person/details/"]'))
                    .find(anchor => {
                        const id = ((anchor.getAttribute('href') || '').match(/\\/tree\\/person\\/details\\/([A-Z0-9-]+)/i) || [])[1];
                        return id && id.toUpperCase() !== normalizedPersonId && !summaries.some(child => child.id === id.toUpperCase()) && familyText.includes(clean(anchor.textContent));
                    });

                if (spouseLink) {
                    const spouseId = (spouseLink.getAttribute('href').match(/\\/tree\\/person\\/details\\/([A-Z0-9-]+)/i) || [])[1].toUpperCase();
                    await sleep(900);
                    spouse = await visitPerson(spouseId);
                    await sleep(900);
                    await visitPerson(normalizedPersonId);
                }

                const children = [];
                for (const summary of summaries) {
                    await sleep(900);
                    const detail = await visitPerson(summary.id);
                    children.push({
                        id: summary.id,
                        name: detail.name || summary.name,
                        birthDate: detail.birthDate || summary.birthDate,
                        birthPlace: detail.birthPlace || summary.birthPlace,
                        deathDate: detail.deathDate || summary.deathDate,
                        deathPlace: detail.deathPlace || summary.deathPlace,
                        lifeSpan: summary.lifeSpan
                    });
                }

                if (personIdFromURL() !== normalizedPersonId) {
                    await sleep(900);
                    await visitPerson(normalizedPersonId);
                }

                const result = {
                    sourcePersonId: normalizedPersonId,
                    focusPerson,
                    spouse,
                    marriage,
                    children
                };

                await postResult(result);
                return result;
            };
        })();
        """
    }

    private static func escapeJavaScript(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
