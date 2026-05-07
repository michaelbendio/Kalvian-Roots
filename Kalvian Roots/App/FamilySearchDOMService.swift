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

struct FamilySearchVitalSummary: Codable, Equatable, Hashable {
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
    var sex: String? = nil
    var summaryYears: String? = nil
    var birthDate: String?
    var birthPlace: String?
    var deathDate: String?
    var deathPlace: String?
    var christeningDate: String? = nil
    var christeningPlace: String? = nil
    var burialDate: String? = nil
    var burialPlace: String? = nil
    var birth: FamilySearchVitalSummary? = nil
    var christening: FamilySearchVitalSummary? = nil
    var death: FamilySearchVitalSummary? = nil
    var burial: FamilySearchVitalSummary? = nil
    var lifeSpan: String?
    var extractionStatus: String? = nil
    var extractionNotes: [String]? = nil
}

struct FamilySearchFamilyExtraction: Codable, Equatable, Hashable {
    var sourcePersonId: String
    var parentFamilySearchId: String? = nil
    var extractedAt: String? = nil
    var sourceUrl: String? = nil
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
                identityName: comparisonGivenName(from: child.name),
                birthDate: dateParser(firstNonBlank(child.birthDate, child.birth?.date, child.christeningDate, child.christening?.date)),
                deathDate: dateParser(firstNonBlank(child.deathDate, child.death?.date, child.burialDate, child.burial?.date)),
                source: .familySearch,
                nameManager: nameManager,
                familySearchId: child.id,
                hiskiCitation: nil
            )
        }
    }

    private static func firstNonBlank(_ values: String?...) -> String? {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private static func comparisonGivenName(from name: String) -> String {
        name
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init) ?? name
    }

    static func makeAtlasExtractorScript(callbackURL: String? = nil) -> String {
        let callbackLine: String
        if let callbackURL {
            callbackLine = "const KALVIAN_ROOTS_CALLBACK_URL = '\(escapeJavaScript(callbackURL))';"
        } else {
            callbackLine = "const KALVIAN_ROOTS_CALLBACK_URL = 'http://127.0.0.1:8081/familysearch/extraction-result';"
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
                const textBlockVital = vitalFromTextBlock(extractionDocument(), label);
                if (textBlockVital) {
                    return textBlockVital;
                }

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
                const personName = cleanPersonName(name);
                if (!idMatch || !personName) return null;
                return {
                    id: idMatch[0].toUpperCase(),
                    name: personName,
                    sex: null,
                    summaryYears: summaryYearsFromDetail(detail),
                    birthDate: null,
                    birthPlace: null,
                    deathDate: null,
                    deathPlace: null,
                    lifeSpan: summaryYearsFromDetail(detail)
                };
            }

            function cleanPersonName(name) {
                const text = clean(name)
                    .replace(/\\b[A-Z0-9]{4}-[A-Z0-9]{3,}\\b/ig, '')
                    .replace(/[•·]/g, '')
                    .trim();
                if (!text) return '';
                if (/^(Preferred|Marriage|Children\\s*\\(\\d+\\)|Add Child|Add Spouse|Parents and Siblings|Spouses and Children)$/i.test(text)) return '';
                if (/^[\\d\\s–\\-—?]+$/.test(text)) return '';
                return text;
            }

            function summaryYearsFromDetail(detail) {
                const value = clean(detail)
                    .replace(/\\b[A-Z0-9]{4}-[A-Z0-9]{3,}\\b/ig, '')
                    .replace(/[•·]/g, '')
                    .trim();
                return value || null;
            }

            function personEntryParseAt(lines, index) {
                if (index >= lines.length) return null;

                for (let offset = 0; offset <= 4 && index + offset < lines.length; offset += 1) {
                    const idLine = lines[index + offset];
                    if (!/\\b[A-Z0-9]{4}-[A-Z0-9]{3,}\\b/i.test(clean(idLine))) continue;

                    const nameCandidates = [
                        lines[index],
                        lines[index + offset - 1],
                        lines[index + offset - 2],
                        lines[index + offset - 3],
                        lines[index + 1]
                    ];
                    const name = nameCandidates.map(cleanPersonName).find(Boolean);
                    if (!name) return null;

                    const detail = lines
                        .slice(index, index + offset + 1)
                        .filter(line => clean(line) !== name)
                        .join(' ');
                    const person = personFromNameAndDetail(name, detail);
                    return person ? { person, nextIndex: index + offset + 1 } : null;
                }

                if (index + 1 >= lines.length) return null;
                const person = personFromNameAndDetail(lines[index], lines[index + 1]);
                return person ? { person, nextIndex: index + 2 } : null;
            }

            function personEntryAt(lines, index) {
                const parsed = personEntryParseAt(lines, index);
                return parsed ? parsed.person : null;
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

                    const parsed = personEntryParseAt(lines, index);
                    if (parsed) {
                        group.spouses.push(parsed.person);
                        index = parsed.nextIndex;
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

                    const parsed = personEntryParseAt(lines, index);
                    if (parsed) {
                        const nextAfterEntry = lines[parsed.nextIndex] || '';
                        if (/^Marriage$/i.test(nextAfterEntry) || /^Children\\s*\\(\\d+\\)$/i.test(nextAfterEntry)) {
                            break;
                        }
                        group.children.push(parsed.person);
                        index = parsed.nextIndex;
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

            function visibleText(element) {
                if (!element) return '';
                const style = localDocument.defaultView.getComputedStyle(element);
                if (style.display === 'none' || style.visibility === 'hidden' || Number(style.opacity) === 0) return '';
                return clean(element.innerText || element.textContent || '');
            }

            function isEditControl(element) {
                const label = clean(element.getAttribute('aria-label') || element.getAttribute('title') || element.textContent || '');
                return /\\b(Edit|Pencil)\\b/i.test(label);
            }

            function childCardFor(element, id) {
                let current = element;
                while (current && current !== localDocument.body) {
                    if (visibleText(current).includes(id)) {
                        return current;
                    }
                    current = current.parentElement;
                }
                return null;
            }

            function clickableNameControl(summary) {
                const scopedRoot = familyMembersSection() || localDocument;
                const candidates = Array.from(scopedRoot.querySelectorAll('a,button,[role="button"],[tabindex],span,div'))
                    .filter(element => {
                        if (!visibleText(element).includes(summary.name)) return false;
                        if (isEditControl(element)) return false;
                        return !!childCardFor(element, summary.id);
                    })
                    .sort((a, b) => visibleText(a).length - visibleText(b).length);

                const best = candidates[0];
                if (!best) return null;
                return best.closest('a,button,[role="button"],[tabindex]') || best;
            }

            function candidateChildControls(id) {
                const scopedRoot = familyMembersSection() || localDocument;
                const selectors = [
                    'a[href*="/tree/person/details/' + id + '"]',
                    'a[href*="/tree/person/' + id + '"]',
                    'button[aria-label*="' + id + '"]',
                    '[role="button"][aria-label*="' + id + '"]',
                    '[data-testid*="' + id + '"]'
                ];
                const direct = selectors.flatMap(selector => Array.from(scopedRoot.querySelectorAll(selector)));
                const byText = Array.from(scopedRoot.querySelectorAll('a,button,[role="button"],[tabindex]')).filter(element => {
                    const text = clean(element.getAttribute('aria-label') || element.textContent || '');
                    return text.includes(id) && !isEditControl(element);
                });
                return Array.from(new Set(direct.concat(byText))).filter(element => visibleText(element) && !isEditControl(element));
            }

            function findChildControl(summary) {
                const nameControl = clickableNameControl(summary);
                if (nameControl) {
                    return nameControl;
                }

                const controls = candidateChildControls(summary.id);
                if (controls.length > 0) {
                    return controls.find(element => visibleText(element).includes(summary.name)) || controls[0];
                }

                const scopedRoot = familyMembersSection() || localDocument;
                return Array.from(scopedRoot.querySelectorAll('a,button,[role="button"],[tabindex]'))
                    .find(element => {
                        const text = visibleText(element);
                        return text.includes(summary.name) && text.includes(summary.id) && !isEditControl(element);
                    }) || null;
            }

            function panelCandidatesFor(id) {
                const familySection = familyMembersSection();
                return Array.from(localDocument.querySelectorAll('[role="dialog"],[aria-modal="true"],aside,section,article,[data-testid],div'))
                    .filter(element => {
                        const text = visibleText(element);
                        const testId = clean(element.getAttribute('data-testid') || '').toLowerCase();
                        const isOverlayLike = element.matches('[role="dialog"],[aria-modal="true"],aside') || /panel|drawer|flyout/.test(testId);
                        if (familySection && familySection.contains(element) && !isOverlayLike) {
                            return false;
                        }
                        return text.includes(id) &&
                            /\\b(Birth|Christening|Death|Burial|Sex)\\b/i.test(text) &&
                            element.offsetWidth > 0 &&
                            element.offsetHeight > 0;
                    })
                    .sort((a, b) => visibleText(a).length - visibleText(b).length);
            }

            async function waitForChildPanel(id, ignoredPanels) {
                for (let attempt = 0; attempt < 40; attempt += 1) {
                    const panels = panelCandidatesFor(id).filter(panel => !ignoredPanels || !ignoredPanels.has(panel));
                    if (panels.length > 0) {
                        return panels[0];
                    }
                    await sleep(250);
                }
                throw new Error('child detail panel did not open for ' + id);
            }

            function linesFrom(element) {
                return (element ? (element.innerText || element.textContent || '') : '')
                    .split('\\n')
                    .map(clean)
                    .filter(Boolean);
            }

            function isVitalLabel(line) {
                return /^(Birth|Born|Christening|Christened|Baptism|Baptized|Death|Died|Burial|Buried|Sex|Parents and Siblings|Spouses and Children|Vitals)$/i.test(clean(line));
            }

            function vitalLabelsFor(label) {
                if (label === 'Birth') return ['Birth', 'Born'];
                if (label === 'Christening') return ['Christening', 'Christened', 'Baptism', 'Baptized'];
                if (label === 'Death') return ['Death', 'Died'];
                if (label === 'Burial') return ['Burial', 'Buried'];
                return [label];
            }

            function dateLikeFromText(text) {
                const value = clean(text);
                const fullDate = value.match(/\\b\\d{1,2}\\s+[A-Za-zÅÄÖåäö.]+\\s+\\d{3,4}\\b/);
                if (fullDate) return fullDate[0];
                const dottedDate = value.match(/\\b\\d{1,2}\\.\\d{1,2}\\.\\d{3,4}\\b/);
                if (dottedDate) return dottedDate[0];
                const monthYear = value.match(/\\b[A-Za-zÅÄÖåäö.]+\\s+\\d{3,4}\\b/);
                if (monthYear) return monthYear[0];
                const year = value.match(/\\b\\d{3,4}\\b/);
                return year ? year[0] : null;
            }

            function splitVitalLine(text, labels) {
                let value = clean(text);
                for (const label of labels) {
                    value = value.replace(new RegExp('^' + label + '\\\\b[:\\\\s•·-]*', 'i'), '');
                }
                value = clean(value);
                const date = dateLikeFromText(value);
                if (!date) return null;
                const place = clean(value.slice(value.indexOf(date) + date.length).replace(/^[•·,;:-]+/, '')) || null;
                return { date, place };
            }

            function vitalFromTextBlock(panel, label) {
                const labels = vitalLabelsFor(label);
                const lines = linesFrom(panel);

                for (const line of lines) {
                    if (labels.some(vitalLabel => new RegExp('^' + vitalLabel + '\\\\b', 'i').test(line))) {
                        const parsed = splitVitalLine(line, labels);
                        if (parsed) return parsed;
                    }
                }

                const text = lines.join('\\n');
                const labelPattern = labels.join('|');
                const nextLabelPattern = 'Birth|Born|Christening|Christened|Baptism|Baptized|Death|Died|Burial|Buried|Sex|Parents and Siblings|Spouses and Children|Vitals';
                const match = text.match(new RegExp('(?:' + labelPattern + ')\\\\s*[:\\\\n ]+([\\\\s\\\\S]*?)(?=\\\\n(?:' + nextLabelPattern + ')\\\\b|$)', 'i'));
                if (!match) return null;
                const segmentLines = match[1].split('\\n').map(clean).filter(Boolean);
                if (segmentLines.length === 0) return null;
                const date = dateLikeFromText(segmentLines[0]) || dateLikeFromText(match[1]);
                if (!date) return null;
                const place = segmentLines.length > 1
                    ? segmentLines[1]
                    : clean(match[1].slice(match[1].indexOf(date) + date.length).replace(/^[•·,;:-]+/, '')) || null;
                return { date, place };
            }

            function vitalFromPanel(panel, label) {
                const textBlockVital = vitalFromTextBlock(panel, label);
                if (textBlockVital) {
                    return textBlockVital;
                }

                const lines = linesFrom(panel);
                const labels = vitalLabelsFor(label);
                const index = lines.findIndex(line => labels.some(vitalLabel => clean(line) === vitalLabel));
                if (index < 0) {
                    return { date: null, place: null };
                }

                const values = [];
                for (let i = index + 1; i < lines.length && values.length < 2; i += 1) {
                    if (isVitalLabel(lines[i])) break;
                    values.push(lines[i]);
                }

                return {
                    date: values[0] || null,
                    place: values[1] || null
                };
            }

            function sexFromPanel(panel) {
                const lines = linesFrom(panel);
                const index = lines.findIndex(line => clean(line) === 'Sex');
                if (index >= 0 && lines[index + 1] && !isVitalLabel(lines[index + 1])) {
                    return lines[index + 1];
                }
                const text = visibleText(panel);
                const match = text.match(/\\b(Male|Female|Unknown)\\b/i);
                return match ? match[1] : null;
            }

            function closeChildPanel() {
                const closeButton = Array.from(localDocument.querySelectorAll('button,[role="button"]'))
                    .find(element => /close/i.test(clean(element.getAttribute('aria-label') || element.textContent || '')));
                if (closeButton) {
                    closeButton.click();
                } else {
                    localDocument.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
                }
            }

            async function withBlockedChildNavigation(summary, action) {
                const originalPushState = window.history.pushState;
                const originalReplaceState = window.history.replaceState;

                function isBlockedChildURL(url) {
                    if (!url) return false;
                    try {
                        const parsed = new URL(url, window.location.href);
                        return parsed.hostname === window.location.hostname &&
                            new RegExp('/tree/person/(details/)?' + summary.id + '($|[/?#])', 'i').test(parsed.pathname);
                    } catch (_) {
                        return false;
                    }
                }

                function blockChildLink(event) {
                    const link = event.target && event.target.closest && event.target.closest('a[href]');
                    if (link && isBlockedChildURL(link.href)) {
                        event.preventDefault();
                    }
                }

                window.history.pushState = function (state, title, url) {
                    if (isBlockedChildURL(url)) return;
                    return originalPushState.apply(window.history, arguments);
                };
                window.history.replaceState = function (state, title, url) {
                    if (isBlockedChildURL(url)) return;
                    return originalReplaceState.apply(window.history, arguments);
                };
                localDocument.addEventListener('click', blockChildLink, true);

                try {
                    return await action();
                } finally {
                    localDocument.removeEventListener('click', blockChildLink, true);
                    window.history.pushState = originalPushState;
                    window.history.replaceState = originalReplaceState;
                }
            }

            async function extractChildDetailsFromPanel(summary, notes) {
                const ignoredPanels = new Set(panelCandidatesFor(summary.id));
                const control = findChildControl(summary);
                if (!control) {
                    throw new Error('child detail control not found for ' + summary.id);
                }

                const panel = await withBlockedChildNavigation(summary, async function () {
                    control.click();
                    return await waitForChildPanel(summary.id, ignoredPanels);
                });
                const birth = vitalFromPanel(panel, 'Birth');
                const christening = vitalFromPanel(panel, 'Christening');
                const death = vitalFromPanel(panel, 'Death');
                const burial = vitalFromPanel(panel, 'Burial');

                try {
                    return {
                        id: summary.id,
                        name: summary.name,
                        sex: sexFromPanel(panel) || summary.sex || null,
                        summaryYears: summary.summaryYears || summary.lifeSpan || null,
                        birth,
                        birthDate: birth.date,
                        birthPlace: birth.place,
                        christening,
                        christeningDate: christening.date,
                        christeningPlace: christening.place,
                        death,
                        deathDate: death.date,
                        deathPlace: death.place,
                        burial,
                        burialDate: burial.date,
                        burialPlace: burial.place,
                        lifeSpan: summary.lifeSpan || summary.summaryYears || null,
                        extractionStatus: 'success',
                        extractionSource: 'panelFallback',
                        extractionNotes: notes
                    };
                } finally {
                    closeChildPanel();
                    await sleep(250);
                }
            }

            async function extractChildDetails(summary) {
                const notes = [];
                try {
                    notes.push('using child panel extraction');
                    return await extractChildDetailsFromPanel(summary, notes);
                } catch (error) {
                    notes.push(clean(error && error.message));
                    console.warn('Kalvian Roots FamilySearch child extraction failed for ' + summary.id + ':', error);
                    closeChildPanel();
                    await sleep(250);
                    return {
                        id: summary.id,
                        name: summary.name,
                        sex: summary.sex || null,
                        summaryYears: summary.summaryYears || summary.lifeSpan || null,
                        birth: { date: summary.birthDate || null, place: summary.birthPlace || null },
                        birthDate: summary.birthDate || null,
                        birthPlace: summary.birthPlace || null,
                        christening: { date: null, place: null },
                        christeningDate: null,
                        christeningPlace: null,
                        death: { date: summary.deathDate || null, place: summary.deathPlace || null },
                        deathDate: summary.deathDate || null,
                        deathPlace: summary.deathPlace || null,
                        burial: { date: null, place: null },
                        burialDate: null,
                        burialPlace: null,
                        lifeSpan: summary.lifeSpan || summary.summaryYears || null,
                        extractionStatus: 'partial',
                        extractionSource: 'summaryFallback',
                        extractionNotes: notes
                    };
                }
            }

            function assertCurrentFamilySearchDetailsPage(expectedId) {
                if (!isFamilySearchDocument(localDocument)) {
                    console.error('Not on FamilySearch person details page');
                    throw new Error('not on FamilySearch person details page: ' + documentURL(localDocument));
                }

                if (!isPersonDetailsDocument(localDocument)) {
                    console.error('Not on FamilySearch person details page');
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
                if (!KALVIAN_ROOTS_CALLBACK_URL) {
                    console.warn('Kalvian Roots FamilySearch extractor has no callback URL; result was not posted.');
                    return;
                }

                let response = null;
                try {
                    response = await fetch(KALVIAN_ROOTS_CALLBACK_URL, {
                        method: 'POST',
                        mode: 'cors',
                        credentials: 'include',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify(result)
                    });
                } catch (error) {
                    console.error('Kalvian Roots FamilySearch extractor callback POST failed:', error);
                    throw new Error('callback POST failed: ' + clean(error && error.message));
                }

                if (!response.ok) {
                    console.error('Kalvian Roots FamilySearch extractor callback POST failed: HTTP ' + response.status);
                    throw new Error('callback POST failed: HTTP ' + response.status);
                }

                console.info('Kalvian Roots FamilySearch extractor callback POST succeeded.');
            }

            async function postFailureResult(result) {
                try {
                    await postResult(result);
                } catch (error) {
                    console.error('Kalvian Roots FamilySearch extractor failure callback POST failed:', error);
                }
            }

            function failureStatusForError(error) {
                const message = clean(error && error.message);
                if (/not on FamilySearch person details page/i.test(message)) return 'notOnFamilySearch';
                if (/FamilySearch detail frame unavailable/i.test(message)) return 'familySearchDetailUnavailable';
                if (/wrong host for FamilySearch extraction/i.test(message)) return 'wrongHost';
                if (/wrong page type|not on person details page/i.test(message)) return 'wrongPageType';
                if (/expected .* found/i.test(message)) return 'personMismatch';
                if (/callback POST failed/i.test(message)) return 'callbackPostFailed';
                if (/page not ready|timed out/i.test(message)) return 'pageNotReady';
                if (/Spouses and Children section not found/i.test(message)) return 'sectionNotFound';
                if (/spouse groups not found/i.test(message)) return 'spouseGroupsNotFound';
                return 'extractorError';
            }

            function makeFailureResult(expectedPersonId, error) {
                const diagnostics = diagnosticContext();
                return {
                    sourcePersonId: expectedPersonId,
                    parentFamilySearchId: expectedPersonId,
                    extractedAt: new Date().toISOString(),
                    sourceUrl: diagnostics.url,
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
                    console.info('Kalvian Roots FamilySearch extractor started for ' + normalizedPersonId + '.');
                    assertCurrentFamilySearchDetailsPage(normalizedPersonId);
                    const focusPerson = await visitPerson(normalizedPersonId);
                    const spouseGroups = extractSpouseGroups();
                    const preferredGroupIndex = spouseGroups.findIndex(group => group.isPreferred);
                    const selectedGroupIndex = preferredGroupIndex >= 0 ? preferredGroupIndex : 0;
                    const selectedGroup = spouseGroups[selectedGroupIndex];
                    const rawCandidateChildCount = selectedGroup.children.length;

                    let spouse = selectedGroup.spouses.find(person => person.id !== normalizedPersonId) || null;

                    const enrichedSpouseGroups = [];
                    for (const group of spouseGroups) {
                        const enrichedChildren = [];
                        for (const summary of group.children) {
                            await sleep(250);
                            enrichedChildren.push(await extractChildDetails(summary));
                        }
                        enrichedSpouseGroups.push({
                            ...group,
                            children: enrichedChildren
                        });
                    }

                    const selectedEnrichedGroup = enrichedSpouseGroups[selectedGroupIndex];
                    const children = selectedEnrichedGroup.children;
                    const allEnrichedChildren = enrichedSpouseGroups.reduce((all, group) => all.concat(group.children), []);
                    const selectedBirthDateCount = children.filter(child => clean(child.birthDate)).length;
                    const selectedDeathDateCount = children.filter(child => clean(child.deathDate)).length;
                    const allBirthDateCount = allEnrichedChildren.filter(child => clean(child.birthDate)).length;
                    const allDeathDateCount = allEnrichedChildren.filter(child => clean(child.deathDate)).length;
                    const detailsPageChildCount = allEnrichedChildren.filter(child => child.extractionSource === 'detailsPage').length;
                    const panelFallbackChildCount = allEnrichedChildren.filter(child => child.extractionSource === 'panelFallback').length;
                    const summaryFallbackChildCount = allEnrichedChildren.filter(child => child.extractionSource === 'summaryFallback').length;

                    if (personIdFromURL() !== normalizedPersonId) {
                        await sleep(900);
                        await visitPerson(normalizedPersonId);
                    }

                    const diagnostics = diagnosticContext();
                    const result = {
                        sourcePersonId: normalizedPersonId,
                        parentFamilySearchId: normalizedPersonId,
                        extractedAt: new Date().toISOString(),
                        sourceUrl: diagnostics.url,
                        focusPerson,
                        spouse,
                        marriage: selectedEnrichedGroup.marriage,
                        children,
                        spouseGroups: enrichedSpouseGroups,
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
                        spouseGroupCount: enrichedSpouseGroups.length,
                        childCount: children.length,
                        preferredChildCount: selectedEnrichedGroup.children.length,
                        debugNotes: [
                            'FamilySearch extraction finished: spouse groups ' + enrichedSpouseGroups.length + ', preferred group children ' + selectedEnrichedGroup.children.length,
                            'FamilySearch selected group child birth dates extracted: ' + selectedBirthDateCount + '/' + children.length + ', death dates extracted: ' + selectedDeathDateCount + '/' + children.length,
                            'FamilySearch all spouse group child birth dates extracted: ' + allBirthDateCount + '/' + allEnrichedChildren.length + ', death dates extracted: ' + allDeathDateCount + '/' + allEnrichedChildren.length,
                            'FamilySearch child detail sources: details page ' + detailsPageChildCount + ', panel fallback ' + panelFallbackChildCount + ', summary fallback ' + summaryFallbackChildCount
                        ]
                    };

                    if (children.length === 0) {
                        console.warn('Kalvian Roots FamilySearch extractor found zero children; posting result anyway.');
                    }

                    try {
                        await postResult(result);
                        console.info('Kalvian Roots FamilySearch extraction succeeded: ' + children.length + ' children.');
                        alert('Kalvian Roots received FamilySearch extraction for ' + normalizedPersonId + ': ' + children.length + ' children. Return to the local family page.');
                    } catch (postError) {
                        result.status = 'callbackPostFailed';
                        result.failureReason = clean(postError && postError.message);
                        result.debugNotes = result.debugNotes.concat(['FamilySearch callback POST failed: ' + result.failureReason]);
                        console.error('Kalvian Roots FamilySearch extraction completed but callback POST failed:', postError);
                        alert('FamilySearch extraction finished, but Kalvian Roots did not receive it: ' + result.failureReason);
                    }
                    return result;
                } catch (error) {
                    console.error('Kalvian Roots FamilySearch extraction failed:', error);
                    const result = makeFailureResult(normalizedPersonId, error);
                    await postFailureResult(result);
                    return result;
                }
            };
        })();
        """
    }

    static func makeBookmarklet() -> String {
        let extractorScript = makeAtlasExtractorScript()
        let bookmarkletBody = """
        (() => {
        \(extractorScript)
        const match = location.pathname.match(/\\/tree\\/person\\/details\\/([A-Z0-9-]+)/i);
        if (!match) {
            alert('Open a FamilySearch person Details page before running the Kalvian Roots extractor.');
            console.error('Not on FamilySearch person details page');
            return;
        }
        window.extractFamilySearchChildren(match[1].toUpperCase());
        })()
        """
        var allowed = CharacterSet.urlFragmentAllowed
        allowed.remove(charactersIn: "%")
        let encodedBody = bookmarkletBody.addingPercentEncoding(withAllowedCharacters: allowed) ?? bookmarkletBody
        return "javascript:" + encodedBody
    }

    private static func escapeJavaScript(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

}
