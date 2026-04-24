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

struct FamilySearchSpouseGroup: Codable, Equatable, Hashable {
    var spouses: [FamilySearchPersonSummary]
    var marriage: FamilySearchMarriageSummary?
    var declaredChildCount: Int?
    var children: [FamilySearchChild]
    var isPreferred: Bool
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
    var spouseGroups: [FamilySearchSpouseGroup]?
    var status: String?
    var failureReason: String?
    var url: String?
    var pageTitle: String?
    var detectedHost: String?
    var detectedPersonId: String?
    var expectedPersonId: String?
    var isFamilySearchPage: Bool?
    var isPersonDetailsPage: Bool?
    var familyMembersSectionFound: Bool?
    var spousesAndChildrenSectionFound: Bool?
    var childrenMarkerCount: Int?
    var rawCandidateChildCount: Int?
    var spouseGroupCount: Int?
    var childCount: Int?
    var preferredChildCount: Int?
    var debugNotes: [String]?

    var isSuccessful: Bool {
        status == nil || status == "success"
    }
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

            let detailsBaseURL = '\(detailsBaseURL)';
            let localDocument = document;
            let detailFrameId = 'kalvian-roots-familysearch-detail-frame';
            let failedDetailDocuments = new Set();
            let currentDocumentOverride = { value: null };

            function extractionDocument() {
                const doc = currentDocumentOverride.value || localDocument;

                if (isFamilySearchDocument(doc)) {
                    return doc;
                }

                throw new Error('not on FamilySearch person details page: ' + documentURL(doc));
            }

            function diagnosticDocument() {
                try {
                    return extractionDocument();
                } catch (_) {
                    return document;
                }
            }

            function documentHost(doc) {
                try {
                    return doc.location.hostname;
                } catch (_) {
                    return null;
                }
            }

            function documentURL(doc) {
                try {
                    return doc.location.href;
                } catch (_) {
                    return null;
                }
            }

            function documentTitle(doc) {
                try {
                    return clean(doc.title);
                } catch (_) {
                    return '';
                }
            }

            function isFamilySearchDocument(doc) {
                const host = documentHost(doc);
                return /(^|\\.)familysearch\\.org$/i.test(host || '') || /FamilySearch/i.test(documentTitle(doc));
            }

            function isPersonDetailsDocument(doc) {
                try {
                    return /\\/tree\\/person\\/details\\/[A-Z0-9-]+/i.test(doc.location.pathname);
                } catch (_) {
                    return false;
                }
            }

            function personIdFromDocumentURL(doc) {
                try {
                    const match = doc.location.pathname.match(/\\/tree\\/person\\/details\\/([A-Z0-9-]+)/i);
                    return match ? match[1].toUpperCase() : null;
                } catch (_) {
                    return null;
                }
            }

            function personIdFromURL() {
                return personIdFromDocumentURL(extractionDocument());
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

            function pageURL() {
                return documentURL(diagnosticDocument());
            }

            function pageTitle() {
                return documentTitle(diagnosticDocument());
            }

            function pageHost() {
                return documentHost(diagnosticDocument());
            }

            function isFamilySearchPage() {
                return isFamilySearchDocument(diagnosticDocument());
            }

            function isPersonDetailsPage() {
                return isPersonDetailsDocument(diagnosticDocument());
            }

            function extractMarriage() {
                const groups = extractSpouseGroups();
                return groups[0]?.marriage || { date: null, place: null };
            }

            function makeMarriage(date, place) {
                return {
                    date: date || null,
                    place: place || null
                };
            }

            function personFromNameAndDetail(name, detail) {
                const idMatch = clean(detail).match(/\\b[A-Z0-9]{4}-[A-Z0-9]{3,}\\b/i);
                if (!idMatch || !clean(name)) return null;
                return {
                    id: idMatch[0].toUpperCase(),
                    name: clean(name),
                    birthDate: null,
                    birthPlace: null,
                    deathDate: null,
                    deathPlace: null,
                    lifeSpan: clean(detail).replace(/\\s*•\\s*[A-Z0-9]{4}-[A-Z0-9]{3,}\\b/i, '') || null
                };
            }

            function personEntryAt(lines, index) {
                if (index + 1 >= lines.length) return null;
                return personFromNameAndDetail(lines[index], lines[index + 1]);
            }

            function isSpouseGroupBoundary(line) {
                return /^(Preferred|Add Spouse|Parents and Siblings)$/i.test(clean(line));
            }

            function isChildCollectionBoundary(line) {
                return /^(Add Child|Add Spouse|Add Child with an Unknown Mother|Parents and Siblings|Preferred)$/i.test(clean(line));
            }

            function sectionLinesFromSpousesAndChildren() {
                const section = familyMembersSection();
                if (!section) {
                    throw new Error('Spouses and Children section not found: Family Members section not found');
                }

                const lines = (section.innerText || '').split('\\n').map(clean).filter(Boolean);
                const start = lines.findIndex(line => /^Spouses and Children$/i.test(line));
                if (start < 0) {
                    throw new Error('Spouses and Children section not found');
                }

                const end = lines.findIndex((line, index) => index > start && /^Parents and Siblings$/i.test(line));
                return lines.slice(start + 1, end >= 0 ? end : lines.length);
            }

            function diagnosticContext() {
                let section = null;
                try {
                    section = familyMembersSection();
                } catch (_) {
                    section = null;
                }
                const allLines = section ? (section.innerText || '').split('\\n').map(clean).filter(Boolean) : [];
                const spousesIndex = allLines.findIndex(line => /^Spouses and Children$/i.test(line));
                const parentsIndex = allLines.findIndex((line, index) => index > spousesIndex && /^Parents and Siblings$/i.test(line));
                const sectionLines = spousesIndex >= 0
                    ? allLines.slice(spousesIndex + 1, parentsIndex >= 0 ? parentsIndex : allLines.length)
                    : [];

                return {
                    url: pageURL(),
                    pageTitle: pageTitle(),
                    detectedHost: pageHost(),
                    detectedPersonId: personIdFromDocumentURL(diagnosticDocument()),
                    isFamilySearchPage: isFamilySearchPage(),
                    isPersonDetailsPage: isPersonDetailsPage(),
                    familyMembersSectionFound: !!section,
                    spousesAndChildrenSectionFound: spousesIndex >= 0,
                    childrenMarkerCount: sectionLines.filter(line => /^Children\\s*\\(\\d+\\)$/i.test(line)).length
                };
            }

            function parseChildCount(line) {
                const match = clean(line).match(/^Children\\s*\\((\\d+)\\)$/i);
                return match ? parseInt(match[1], 10) : null;
            }

            function parseSpouseGroup(lines, startIndex, expectedPersonId) {
                let index = startIndex;
                const isPreferred = /^Preferred$/i.test(lines[index] || '');
                if (isPreferred) index += 1;

                const group = {
                    spouses: [],
                    marriage: null,
                    declaredChildCount: null,
                    children: [],
                    isPreferred
                };

                while (index + 1 < lines.length) {
                    if (/^Marriage$/i.test(lines[index]) || /^Children\\s*\\(\\d+\\)$/i.test(lines[index]) || isSpouseGroupBoundary(lines[index])) {
                        break;
                    }

                    const person = personEntryAt(lines, index);
                    if (person) {
                        group.spouses.push(person);
                        index += 2;
                    } else {
                        index += 1;
                    }
                }

                const marriageIndex = lines.findIndex((line, i) => i >= index && /^Marriage$/i.test(line));
                const childrenIndex = lines.findIndex((line, i) => i >= index && /^Children\\s*\\(\\d+\\)$/i.test(line));
                if (marriageIndex >= 0 && childrenIndex >= 0 && marriageIndex < childrenIndex) {
                    group.marriage = makeMarriage(lines[marriageIndex + 1], lines[marriageIndex + 2]);
                    index = childrenIndex;
                } else if (childrenIndex >= 0) {
                    index = childrenIndex;
                }

                if (index < lines.length) {
                    group.declaredChildCount = parseChildCount(lines[index]);
                    index += 1;
                }

                while (index < lines.length) {
                    const line = lines[index];
                    if (isChildCollectionBoundary(line)) {
                        break;
                    }

                    const person = personEntryAt(lines, index);
                    if (person) {
                        const nextAfterEntry = lines[index + 2] || '';
                        if (/^Marriage$/i.test(nextAfterEntry) || /^Children\\s*\\(\\d+\\)$/i.test(nextAfterEntry)) {
                            break;
                        }
                        group.children.push(person);
                        index += 2;
                    } else {
                        index += 1;
                    }
                }

                return { group, nextIndex: index };
            }

            function extractSpouseGroups() {
                const lines = sectionLinesFromSpousesAndChildren();
                const groups = [];
                let index = 0;

                while (index < lines.length) {
                    if (/^Add Spouse$/i.test(lines[index]) || /^Add Child with an Unknown Mother$/i.test(lines[index])) {
                        break;
                    }

                    if (/^Preferred$/i.test(lines[index]) || personEntryAt(lines, index)) {
                        const parsed = parseSpouseGroup(lines, index, personIdFromURL());
                        if (parsed.group.spouses.length > 0 || parsed.group.declaredChildCount != null) {
                            groups.push(parsed.group);
                        }
                        index = Math.max(parsed.nextIndex, index + 1);
                    } else {
                        index += 1;
                    }
                }

                if (groups.length === 0) {
                    throw new Error('spouse groups not found in Spouses and Children section');
                }

                return groups;
            }

            function assertCurrentFamilySearchDetailsPage(expectedId) {
                if (!isFamilySearchDocument(localDocument)) {
                    throw new Error('not on FamilySearch person details page: ' + documentURL(localDocument));
                }

                if (!isPersonDetailsDocument(localDocument)) {
                    throw new Error('wrong page type for FamilySearch extraction: ' + documentURL(localDocument));
                }

                const detectedId = personIdFromDocumentURL(localDocument);
                if (detectedId !== expectedId) {
                    throw new Error('expected ' + expectedId + ', found ' + (detectedId || 'none'));
                }
            }

            function detailFrame() {
                let frame = localDocument.getElementById(detailFrameId);
                if (frame) return frame;

                frame = localDocument.createElement('iframe');
                frame.id = detailFrameId;
                frame.title = 'Kalvian Roots FamilySearch detail loader';
                frame.style.position = 'fixed';
                frame.style.width = '1px';
                frame.style.height = '1px';
                frame.style.left = '-10000px';
                frame.style.top = '-10000px';
                frame.style.opacity = '0';
                frame.setAttribute('aria-hidden', 'true');
                localDocument.body.appendChild(frame);
                return frame;
            }

            function documentForDetailFrame(frame) {
                try {
                    return frame.contentDocument || frame.contentWindow.document;
                } catch (error) {
                    throw new Error('FamilySearch detail frame unavailable: ' + clean(error && error.message));
                }
            }

            async function waitForDetailsPage(expectedId, documentProvider) {
                let lastError = null;
                let lastDocument = null;
                for (let attempt = 0; attempt < 80; attempt += 1) {
                    try {
                        const doc = documentProvider();
                        lastDocument = doc;
                        if (!isFamilySearchDocument(doc)) {
                            const currentURL = documentURL(doc) || pageURL();
                            if (/^about:blank/i.test(currentURL || '')) {
                                lastError = new Error('FamilySearch page not loaded yet: ' + currentURL);
                                await sleep(250);
                                continue;
                            }
                            throw new Error('not on FamilySearch person details page: ' + currentURL);
                        }
                        if (isPersonDetailsDocument(doc) && personIdFromDocumentURL(doc) === expectedId && doc.readyState === 'complete') {
                            await sleep(500);
                            return;
                        }
                    } catch (error) {
                        lastError = error;
                        if (/FamilySearch detail frame unavailable|not on FamilySearch person details page/i.test(clean(error && error.message))) {
                            throw error;
                        }
                    }
                    await sleep(250);
                }

                if (lastError && /FamilySearch detail frame unavailable|not on FamilySearch person details page/i.test(clean(lastError && lastError.message))) {
                    throw lastError;
                }

                const doc = lastDocument || documentProvider();
                if (!isFamilySearchDocument(doc)) {
                    throw new Error('not on FamilySearch person details page: ' + (documentURL(doc) || pageURL()));
                }

                if (!isPersonDetailsDocument(doc)) {
                    throw new Error('wrong page type for FamilySearch extraction: ' + (documentURL(doc) || pageURL()));
                }

                const detectedId = personIdFromDocumentURL(doc);
                if (detectedId !== expectedId) {
                    throw new Error('expected ' + expectedId + ', found ' + (detectedId || 'none'));
                }

                throw new Error('page not ready within timeout for FamilySearch details page ' + expectedId);
            }

            async function visitPerson(personId) {
                const target = detailsBaseURL + personId;
                const currentDoc = extractionDocument();
                if (personIdFromDocumentURL(currentDoc) === personId) {
                    currentDocumentOverride.value = currentDoc;
                    await waitForDetailsPage(personId, function () { return currentDoc; });
                    try {
                        return extractPersonSummary();
                    } finally {
                        currentDocumentOverride.value = null;
                    }
                }

                if (failedDetailDocuments.has(personId)) {
                    throw new Error('page not ready within timeout for FamilySearch details page ' + personId);
                }

                const frame = detailFrame();
                if (documentURL(documentForDetailFrame(frame)) !== target) {
                    frame.src = target;
                }
                await waitForDetailsPage(personId, function () { return documentForDetailFrame(frame); });

                const frameDocument = documentForDetailFrame(frame);
                currentDocumentOverride.value = frameDocument;
                try {
                    return extractPersonSummary();
                } catch (error) {
                    failedDetailDocuments.add(personId);
                    throw error;
                } finally {
                    currentDocumentOverride.value = null;
                }
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

            function failureStatusForError(error) {
                const message = clean(error && error.message);
                if (/not on FamilySearch person details page/i.test(message)) return 'notOnFamilySearch';
                if (/FamilySearch detail frame unavailable/i.test(message)) return 'familySearchDetailUnavailable';
                if (/wrong host for FamilySearch extraction/i.test(message)) return 'wrongHost';
                if (/wrong page type|not on person details page/i.test(message)) return 'wrongPageType';
                if (/expected .* found/i.test(message)) return 'personMismatch';
                if (/page not ready|timed out/i.test(message)) return 'pageNotReady';
                if (/Spouses and Children section not found/i.test(message)) return 'sectionNotFound';
                if (/spouse groups not found/i.test(message)) return 'spouseGroupsNotFound';
                return 'extractorError';
            }

            function makeFailureResult(expectedPersonId, error) {
                const diagnostics = diagnosticContext();
                return {
                    sourcePersonId: expectedPersonId,
                    focusPerson: null,
                    spouse: null,
                    marriage: null,
                    children: [],
                    spouseGroups: [],
                    status: failureStatusForError(error),
                    failureReason: clean(error && error.message) || 'Unknown FamilySearch extraction error',
                    url: diagnostics.url,
                    pageTitle: diagnostics.pageTitle,
                    detectedHost: diagnostics.detectedHost,
                    detectedPersonId: diagnostics.detectedPersonId,
                    expectedPersonId,
                    isFamilySearchPage: diagnostics.isFamilySearchPage,
                    isPersonDetailsPage: diagnostics.isPersonDetailsPage,
                    familyMembersSectionFound: diagnostics.familyMembersSectionFound,
                    spousesAndChildrenSectionFound: diagnostics.spousesAndChildrenSectionFound,
                    childrenMarkerCount: diagnostics.childrenMarkerCount,
                    rawCandidateChildCount: 0,
                    spouseGroupCount: 0,
                    childCount: 0,
                    preferredChildCount: 0,
                    debugNotes: []
                };
            }

            window.extractFamilySearchChildren = async function extractFamilySearchChildren(personId) {
                const normalizedPersonId = clean(personId).toUpperCase();
                try {
                    assertCurrentFamilySearchDetailsPage(normalizedPersonId);
                    const focusPerson = await visitPerson(normalizedPersonId);
                    const spouseGroups = extractSpouseGroups();
                    const preferredGroupIndex = spouseGroups.findIndex(group => group.isPreferred);
                    const selectedGroupIndex = preferredGroupIndex >= 0 ? preferredGroupIndex : 0;
                    const selectedGroup = spouseGroups[selectedGroupIndex];
                    const rawCandidateChildCount = selectedGroup.children.length;

                    let spouse = selectedGroup.spouses.find(person => person.id !== normalizedPersonId) || null;
                    if (spouse) {
                        await sleep(900);
                        spouse = await visitPerson(spouse.id);
                        await sleep(900);
                        await visitPerson(normalizedPersonId);
                    }

                    const children = [];
                    for (const summary of selectedGroup.children) {
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

                    spouseGroups[selectedGroupIndex] = {
                        ...selectedGroup,
                        children
                    };

                    if (personIdFromURL() !== normalizedPersonId) {
                        await sleep(900);
                        await visitPerson(normalizedPersonId);
                    }

                    const diagnostics = diagnosticContext();
                    const result = {
                        sourcePersonId: normalizedPersonId,
                        focusPerson,
                        spouse,
                        marriage: selectedGroup.marriage,
                        children,
                        spouseGroups,
                        status: 'success',
                        failureReason: null,
                        url: diagnostics.url,
                        pageTitle: diagnostics.pageTitle,
                        detectedHost: diagnostics.detectedHost,
                        detectedPersonId: diagnostics.detectedPersonId,
                        expectedPersonId: normalizedPersonId,
                        isFamilySearchPage: diagnostics.isFamilySearchPage,
                        isPersonDetailsPage: diagnostics.isPersonDetailsPage,
                        familyMembersSectionFound: diagnostics.familyMembersSectionFound,
                        spousesAndChildrenSectionFound: diagnostics.spousesAndChildrenSectionFound,
                        childrenMarkerCount: diagnostics.childrenMarkerCount,
                        rawCandidateChildCount,
                        spouseGroupCount: spouseGroups.length,
                        childCount: children.length,
                        preferredChildCount: selectedGroup.children.length,
                        debugNotes: [
                            'FamilySearch extraction finished: spouse groups ' + spouseGroups.length + ', preferred group children ' + selectedGroup.children.length
                        ]
                    };

                    await postResult(result);
                    return result;
                } catch (error) {
                    const result = makeFailureResult(normalizedPersonId, error);
                    await postResult(result);
                    return result;
                }
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
