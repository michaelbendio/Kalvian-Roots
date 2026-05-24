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
    static let webKitExtractionMessageHandler = "kalvianRootsFamilySearchExtraction"

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

    static func makeFamilySearchExtractorScript() -> String {
        return """
        (function () {
            // Keep all parsing local to the visible FamilySearch page and
            // return only structured JSON to the host app.
            function clean(text) {
                return (text || '').replace(/\\s+/g, ' ').trim();
            }

            function sleep(ms) {
                return new Promise(resolve => setTimeout(resolve, ms));
            }

            function setExtractionStage(stage) {
                window.__kalvianRootsFamilySearchStage = clean(stage);
                console.info('Kalvian Roots FamilySearch stage: ' + window.__kalvianRootsFamilySearchStage);
            }

            function currentExtractionStage() {
                return clean(window.__kalvianRootsFamilySearchStage) || 'not started';
            }

            let detailsBaseURL = '\(detailsBaseURL)';
            let localDocument = document;
            let detailFrameId = 'kalvian-roots-familysearch-detail-frame';
            let failedDetailDocuments = new Set();
            let currentDocumentOverride = { value: null };

            // Most extraction reads the live FamilySearch document. Some
            // helpers temporarily parse a fetched child details page, and this
            // override lets the same parsing functions work against that HTML.
            function extractionDocument() {
                if (currentDocumentOverride.value) {
                    return currentDocumentOverride.value;
                }

                const doc = localDocument;

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

            function extractPersonSummaryFromDocument(doc, fallbackId) {
                currentDocumentOverride.value = doc;
                try {
                    const summary = extractPersonSummary();
                    return {
                        ...summary,
                        id: summary.id || fallbackId
                    };
                } finally {
                    currentDocumentOverride.value = null;
                }
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
                let best = null;
                while (current && current !== localDocument.body) {
                    const text = visibleText(current);
                    if (!text.includes(id)) {
                        break;
                    }
                    const ids = text.match(/\\b[A-Z0-9]{4}-[A-Z0-9]{3}\\b/g) || [];
                    if (ids.length > 1) {
                        break;
                    }
                    best = current;
                    current = current.parentElement;
                }
                // The best card is the smallest ancestor that contains this
                // child's ID and no other FamilySearch person IDs.
                return best;
            }

            function childCardById(id) {
                const scopedRoot = familyMembersSection() || localDocument;
                const cards = Array.from(scopedRoot.querySelectorAll('a,button,[role="button"],[tabindex],span,div,li,article,section'))
                    .filter(element => visibleText(element).includes(id) && !isEditControl(element))
                    .map(element => childCardFor(element, id))
                    .filter(Boolean)
                    .sort((a, b) => visibleText(a).length - visibleText(b).length);
                return Array.from(new Set(cards))[0] || null;
            }

            function clickableNameControl(summary) {
                const idCard = childCardById(summary.id);
                const scopedRoot = idCard || familyMembersSection() || localDocument;
                const candidates = Array.from(scopedRoot.querySelectorAll('a,button,[role="button"],[tabindex],span,div'))
                    .filter(element => {
                        const text = visibleText(element);
                        if (isEditControl(element)) return false;
                        if (idCard) {
                            return text.includes(summary.name) || text.includes(summary.id);
                        }
                        return text.includes(summary.name) && !!childCardFor(element, summary.id);
                    })
                    .sort((a, b) => visibleText(a).length - visibleText(b).length);

                const best = candidates[0];
                return best || idCard || null;
            }

            function candidateChildControls(id) {
                const scopedRoot = familyMembersSection() || localDocument;
                const selectors = [
                    'button[aria-label*="' + id + '"]',
                    '[role="button"][aria-label*="' + id + '"]',
                    '[data-testid*="' + id + '"]'
                ];
                const direct = selectors.flatMap(selector => Array.from(scopedRoot.querySelectorAll(selector)));
                const byText = Array.from(scopedRoot.querySelectorAll('button,[role="button"],[tabindex]')).filter(element => {
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
                return Array.from(scopedRoot.querySelectorAll('button,[role="button"],[tabindex],span,div'))
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
                    // Prefer the smallest matching panel so we read the opened
                    // quick-card, not a large page wrapper around it.
                    .sort((a, b) => visibleText(a).length - visibleText(b).length);
            }

            async function waitForChildPanel(id, ignoredPanels) {
                for (let attempt = 0; attempt < 8; attempt += 1) {
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

                const date = dateLikeFromText(values[0]);
                if (!date) {
                    return { date: null, place: null };
                }

                return {
                    date,
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

            async function closeChildPanel(panel, control, childId) {
                function currentPanel() {
                    // FamilySearch can swap or wrap the quick-card node while
                    // it animates. Re-query by child ID so the close loop
                    // follows the visible card instead of a stale element.
                    if (childId) {
                        const panels = panelCandidatesFor(childId);
                        if (panels.length > 0) return panels[0];
                    }
                    return panel &&
                        localDocument.body.contains(panel) &&
                        panel.offsetWidth > 0 &&
                        panel.offsetHeight > 0
                        ? panel
                        : null;
                }

                function panelStillVisible() {
                    return !!currentPanel();
                }

                async function clickCloseControl() {
                    const closeScope = currentPanel() || localDocument;
                    const closeButton = Array.from(closeScope.querySelectorAll('button,[role="button"],a[role="button"]'))
                        .find(element => /close|dismiss/i.test(clean(element.getAttribute('aria-label') || element.getAttribute('title') || element.textContent || '')));
                    if (!closeButton) return false;
                    closeButton.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, view: window }));
                    closeButton.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true, view: window }));
                    closeButton.click();
                    await sleep(100);
                    return !panelStillVisible();
                }

                const active = localDocument.activeElement;
                if (active && typeof active.blur === 'function') {
                    active.blur();
                }

                if (await clickCloseControl()) return;

                for (let attempt = 0; attempt < 2 && panelStillVisible(); attempt += 1) {
                    const activePanel = currentPanel();
                    // FamilySearch quick-cards behave like hover/click UI.
                    // Signal that the pointer left the child control and the
                    // card, then send outside-click and Escape events through
                    // the same document. Do not remove DOM nodes.
                    for (const element of [control, activePanel]) {
                        if (!element) continue;
                        for (const type of ['pointerout', 'pointerleave', 'mouseout', 'mouseleave']) {
                            const event = type.startsWith('pointer') && typeof PointerEvent === 'function'
                                ? new PointerEvent(type, { bubbles: true, cancelable: true, view: window, pointerType: 'mouse' })
                                : new MouseEvent(type, { bubbles: true, cancelable: true, view: window });
                            element.dispatchEvent(event);
                        }
                    }

                    const panelRect = activePanel ? activePanel.getBoundingClientRect() : null;
                    const outsideX = panelRect && panelRect.left > 20
                        ? Math.max(5, panelRect.left - 10)
                        : Math.min(window.innerWidth - 5, (panelRect ? panelRect.right + 10 : 5));
                    const outsideY = panelRect && panelRect.top > 20
                        ? Math.max(5, panelRect.top - 10)
                        : Math.min(window.innerHeight - 5, (panelRect ? panelRect.bottom + 10 : 5));
                    const target = localDocument.elementFromPoint(outsideX, outsideY) || localDocument.body;
                    for (const type of ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click']) {
                        const event = type.startsWith('pointer') && typeof PointerEvent === 'function'
                            ? new PointerEvent(type, { bubbles: true, cancelable: true, view: window, clientX: outsideX, clientY: outsideY, pointerType: 'mouse' })
                            : new MouseEvent(type, { bubbles: true, cancelable: true, view: window, clientX: outsideX, clientY: outsideY });
                        target.dispatchEvent(event);
                        localDocument.dispatchEvent(event);
                        window.dispatchEvent(event);
                    }

                    const escapeEvent = new KeyboardEvent('keydown', {
                        key: 'Escape',
                        code: 'Escape',
                        keyCode: 27,
                        which: 27,
                        bubbles: true,
                        cancelable: true
                    });
                    localDocument.dispatchEvent(escapeEvent);
                    window.dispatchEvent(escapeEvent);
                    await sleep(100);
                    if (await clickCloseControl()) return;
                }
            }

            function showExtractionSuccessMessage(message) {
                localDocument.getElementById('kalvian-roots-familysearch-success')?.remove();

                const banner = localDocument.createElement('div');
                banner.id = 'kalvian-roots-familysearch-success';
                banner.setAttribute('role', 'status');
                banner.style.position = 'fixed';
                banner.style.zIndex = '2147483647';
                banner.style.right = '24px';
                banner.style.bottom = '24px';
                banner.style.maxWidth = '420px';
                banner.style.padding = '14px 44px 14px 18px';
                banner.style.borderRadius = '8px';
                banner.style.background = '#0f5132';
                banner.style.color = '#fff';
                banner.style.boxShadow = '0 8px 24px rgba(0,0,0,0.24)';
                banner.style.font = '15px system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif';
                banner.style.lineHeight = '1.4';
                banner.textContent = message;

                const closeButton = localDocument.createElement('button');
                closeButton.type = 'button';
                closeButton.setAttribute('aria-label', 'Dismiss Kalvian Roots extraction message');
                closeButton.textContent = '×';
                closeButton.style.position = 'absolute';
                closeButton.style.top = '6px';
                closeButton.style.right = '10px';
                closeButton.style.border = '0';
                closeButton.style.background = 'transparent';
                closeButton.style.color = '#fff';
                closeButton.style.font = '24px/1 system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif';
                closeButton.style.cursor = 'pointer';
                closeButton.addEventListener('click', function () {
                    banner.remove();
                });
                banner.appendChild(closeButton);
                localDocument.body.appendChild(banner);
                window.setTimeout(function () {
                    banner.remove();
                }, 5000);
            }

            async function withBlockedChildNavigation(summary, action) {
                const originalPushState = window.history.pushState;
                const originalReplaceState = window.history.replaceState;
                let blockedNavigationCount = 0;
                let blockedNavigationURL = null;

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
                        blockedNavigationCount += 1;
                        blockedNavigationURL = link.href;
                        event.preventDefault();
                    }
                }

                window.history.pushState = function (state, title, url) {
                    if (isBlockedChildURL(url)) {
                        blockedNavigationCount += 1;
                        blockedNavigationURL = url;
                        return;
                    }
                    return originalPushState.apply(window.history, arguments);
                };
                window.history.replaceState = function (state, title, url) {
                    if (isBlockedChildURL(url)) {
                        blockedNavigationCount += 1;
                        blockedNavigationURL = url;
                        return;
                    }
                    return originalReplaceState.apply(window.history, arguments);
                };
                localDocument.addEventListener('click', blockChildLink, true);

                try {
                    const value = await action();
                    return { value, blockedNavigationCount, blockedNavigationURL };
                } finally {
                    localDocument.removeEventListener('click', blockChildLink, true);
                    window.history.pushState = originalPushState;
                    window.history.replaceState = originalReplaceState;
                }
            }

            async function openChildQuickCard(summary, control, ignoredPanels) {
                if (control.scrollIntoView) {
                    control.scrollIntoView({ block: 'center', inline: 'nearest' });
                    await sleep(100);
                }

                // FamilySearch may open a child quick-card from hover, focus,
                // or click depending on the current page state. The fallback
                // extractor fires the same short sequence a user gesture would
                // naturally produce, then reads and closes the resulting card.
                const pointerEvent = typeof PointerEvent === 'function'
                    ? new PointerEvent('pointerover', { bubbles: true, cancelable: true, view: window, pointerType: 'mouse' })
                    : new MouseEvent('mouseover', { bubbles: true, cancelable: true, view: window });
                control.dispatchEvent(pointerEvent);
                control.dispatchEvent(new MouseEvent('mouseenter', { bubbles: true, cancelable: true, view: window }));
                control.dispatchEvent(new MouseEvent('mouseover', { bubbles: true, cancelable: true, view: window }));
                control.dispatchEvent(new MouseEvent('mousemove', { bubbles: true, cancelable: true, view: window }));
                if (typeof control.focus === 'function') {
                    control.focus({ preventScroll: true });
                }
                control.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, view: window }));
                control.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true, view: window }));
                control.click();

                return await waitForChildPanel(summary.id, ignoredPanels);
            }

            async function extractChildDetailsFromPanel(summary, notes) {
                const ignoredPanels = new Set(panelCandidatesFor(summary.id));
                const control = findChildControl(summary);
                if (!control) {
                    throw new Error('child detail control not found for ' + summary.id);
                }

                notes.push('using child quick-card click extraction');
                const panelResult = await withBlockedChildNavigation(summary, async function () {
                    return await openChildQuickCard(summary, control, ignoredPanels);
                });
                const panel = panelResult.value;
                if (panelResult.blockedNavigationCount > 0) {
                    notes.push('blocked child detail navigation ' + panelResult.blockedNavigationCount + ' time(s)' + (panelResult.blockedNavigationURL ? ': ' + panelResult.blockedNavigationURL : ''));
                }
                try {
                    const birth = vitalFromPanel(panel, 'Birth');
                    const christening = vitalFromPanel(panel, 'Christening');
                    const death = vitalFromPanel(panel, 'Death');
                    const burial = vitalFromPanel(panel, 'Burial');
                    if (!clean(birth.date) && !clean(christening.date) && !clean(death.date) && !clean(burial.date)) {
                        throw new Error('child quick-card contained no extracted vital dates for ' + summary.id);
                    }

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
                    await closeChildPanel(panel, control, summary.id);
                }
            }

            async function extractChildDetails(summary) {
                const notes = [];
                try {
                    // Open the child's quick-card from the already visible
                    // FamilySearch page, read the full vital facts visible
                    // there, then close the card before moving on.
                    return await extractChildDetailsFromPanel(summary, notes);
                } catch (error) {
                    notes.push(clean(error && error.message));
                }
                console.warn('Kalvian Roots FamilySearch child extraction failed for ' + summary.id + ':', notes.join(' | '));
                // Fallback: keep the summary data already visible on the
                // parent page as partial context only. Its life-span text is
                // often year-only, so do not promote it into exact vital dates.
                return {
                    id: summary.id,
                    name: summary.name,
                    sex: summary.sex || null,
                    summaryYears: summary.summaryYears || summary.lifeSpan || null,
                    birth: { date: null, place: null },
                    birthDate: null,
                    birthPlace: null,
                    christening: { date: null, place: null },
                    christeningDate: null,
                    christeningPlace: null,
                    death: { date: null, place: null },
                    deathDate: null,
                    deathPlace: null,
                    burial: { date: null, place: null },
                    burialDate: null,
                    burialPlace: null,
                    lifeSpan: summary.lifeSpan || summary.summaryYears || null,
                    extractionStatus: 'partial',
                    extractionSource: 'summaryFallback',
                    extractionNotes: notes
                };
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

            async function waitForFamilyMembersSection(expectedId) {
                let lastDiagnostics = null;
                for (let attempt = 0; attempt < 120; attempt += 1) {
                    assertCurrentFamilySearchDetailsPage(expectedId);
                    lastDiagnostics = diagnosticContext();
                    if (lastDiagnostics.familyMembersSectionFound && lastDiagnostics.spousesAndChildrenSectionFound) {
                        return;
                    }

                    await sleep(500);
                }

                const familyMembersMessage = lastDiagnostics && lastDiagnostics.familyMembersSectionFound
                    ? ''
                    : ': Family Members section not found';
                throw new Error('Spouses and Children section not found' + familyMembersMessage);
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

            function cleanupDetailFrame() {
                currentDocumentOverride.value = null;
                const frame = localDocument.getElementById(detailFrameId);
                if (!frame) return;

                try {
                    frame.src = 'about:blank';
                } catch (_) {
                }
                frame.remove();
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
                    debugNotes: ['FamilySearch extraction stage at failure: ' + currentExtractionStage()]
                };
            }

            window.extractFamilySearchChildren = async function extractFamilySearchChildren(personId) {
                const normalizedPersonId = clean(personId).toUpperCase();
                try {
                    console.info('Kalvian Roots FamilySearch extractor started for ' + normalizedPersonId + '.');
                    setExtractionStage('started for ' + normalizedPersonId);
                    cleanupDetailFrame();
                    setExtractionStage('validating details page for ' + normalizedPersonId);
                    assertCurrentFamilySearchDetailsPage(normalizedPersonId);
                    setExtractionStage('waiting for Family Members section');
                    await waitForFamilyMembersSection(normalizedPersonId);
                    setExtractionStage('reading focus person ' + normalizedPersonId);
                    const focusPerson = await visitPerson(normalizedPersonId);
                    setExtractionStage('reading spouse groups');
                    const spouseGroups = extractSpouseGroups();
                    const preferredGroupIndex = spouseGroups.findIndex(group => group.isPreferred);
                    const selectedGroupIndex = preferredGroupIndex >= 0 ? preferredGroupIndex : 0;
                    const selectedGroup = spouseGroups[selectedGroupIndex];
                    const rawCandidateChildCount = selectedGroup.children.length;

                    let spouse = selectedGroup.spouses.find(person => person.id !== normalizedPersonId) || null;

                    const enrichedSpouseGroups = [];
                    for (let groupIndex = 0; groupIndex < spouseGroups.length; groupIndex += 1) {
                        const group = spouseGroups[groupIndex];
                        const enrichedChildren = [];
                        for (let childIndex = 0; childIndex < group.children.length; childIndex += 1) {
                            const summary = group.children[childIndex];
                            // Process one child at a time so each quick-card
                            // fallback has time to open, be read, and close.
                            setExtractionStage('extracting child ' + (childIndex + 1) + '/' + group.children.length + ' in spouse group ' + (groupIndex + 1) + '/' + spouseGroups.length + ': ' + summary.id + ' ' + summary.name);
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
                    const panelFallbackChildCount = allEnrichedChildren.filter(child => child.extractionSource === 'panelFallback').length;
                    const summaryFallbackChildCount = allEnrichedChildren.filter(child => child.extractionSource === 'summaryFallback').length;
                    const childExtractionNoteSamples = allEnrichedChildren
                        .filter(child => Array.isArray(child.extractionNotes) && child.extractionNotes.length > 0)
                        .slice(0, 8)
                        .map(child => 'FamilySearch child extraction note ' + child.id + ' ' + child.name + ': ' + child.extractionNotes.join(' | ').slice(0, 360));

                    if (personIdFromURL() !== normalizedPersonId) {
                        setExtractionStage('returning to focus person ' + normalizedPersonId);
                        await sleep(900);
                        await visitPerson(normalizedPersonId);
                    }

                    setExtractionStage('building extraction result');
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
                            'FamilySearch extraction final stage: ' + currentExtractionStage(),
                            'FamilySearch extraction finished: spouse groups ' + enrichedSpouseGroups.length + ', preferred group children ' + selectedEnrichedGroup.children.length,
                            'FamilySearch selected group child birth dates extracted: ' + selectedBirthDateCount + '/' + children.length + ', death dates extracted: ' + selectedDeathDateCount + '/' + children.length,
                            'FamilySearch all spouse group child birth dates extracted: ' + allBirthDateCount + '/' + allEnrichedChildren.length + ', death dates extracted: ' + allDeathDateCount + '/' + allEnrichedChildren.length,
                            'FamilySearch child detail sources: quick-card ' + panelFallbackChildCount + ', summary fallback ' + summaryFallbackChildCount
                        ].concat(childExtractionNoteSamples)
                    };

                    if (children.length === 0) {
                        console.warn('Kalvian Roots FamilySearch extractor found zero children; posting result anyway.');
                    }

                    await closeChildPanel();
                    setExtractionStage('posting success result');
                    console.info('Kalvian Roots FamilySearch extraction succeeded: ' + children.length + ' children.');
                    showExtractionSuccessMessage('Kalvian Roots extracted FamilySearch children for ' + normalizedPersonId + ': ' + children.length + ' children.');
                    return result;
                } catch (error) {
                    console.error('Kalvian Roots FamilySearch extraction failed:', error);
                    const result = makeFailureResult(normalizedPersonId, error);
                    return result;
                } finally {
                    cleanupDetailFrame();
                }
            };
        })();
        """
    }

    static func makeWebKitExtractionScript(for personId: String) -> String {
        makeWebKitExtractionScript(expectedPersonId: personId)
    }

    static func makeWebKitExtractionScriptForCurrentPage() -> String {
        makeWebKitExtractionScript(expectedPersonId: nil)
    }

    private static func makeWebKitExtractionScript(expectedPersonId: String?) -> String {
        let normalizedPersonId = expectedPersonId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() ?? ""
        let extractorScript = makeFamilySearchExtractorScript()

        return """
        (() => {
            const KALVIAN_ROOTS_WEBKIT_EXPECTED_PERSON_ID = '\(escapeJavaScript(normalizedPersonId))';
            const KALVIAN_ROOTS_WEBKIT_PERSON_ID = KALVIAN_ROOTS_WEBKIT_EXPECTED_PERSON_ID || ((window.location.pathname.match(/\\/tree\\/person\\/details\\/([A-Z0-9-]+)/i) || [])[1] || '').toUpperCase();
            const KALVIAN_ROOTS_WEBKIT_HANDLER = '\(webKitExtractionMessageHandler)';
            const KALVIAN_ROOTS_WEBKIT_TIMEOUT_MS = 90000;
            let didPostKalvianRootsExtractionResult = false;

            function cleanWebKitMessage(text) {
                return (text || '').replace(/\\s+/g, ' ').trim();
            }

            function detectedWebKitPersonId() {
                return ((window.location.pathname.match(/\\/tree\\/person\\/details\\/([A-Z0-9-]+)/i) || [])[1] || '').toUpperCase() || null;
            }

            function webKitExtractionStage() {
                return cleanWebKitMessage(window.__kalvianRootsFamilySearchStage) || 'not reported';
            }

            function postWebKitExtractionResult(result) {
                if (didPostKalvianRootsExtractionResult) {
                    return;
                }
                didPostKalvianRootsExtractionResult = true;
                window.webkit.messageHandlers[KALVIAN_ROOTS_WEBKIT_HANDLER].postMessage(JSON.stringify(result));
            }

            function makeWebKitFailureResult(status, reason, notes) {
                return {
                    sourcePersonId: KALVIAN_ROOTS_WEBKIT_PERSON_ID,
                    parentFamilySearchId: KALVIAN_ROOTS_WEBKIT_PERSON_ID || null,
                    extractedAt: new Date().toISOString(),
                    sourceUrl: window.location.href,
                    children: [],
                    spouseGroups: [],
                    status,
                    failureReason: reason,
                    url: window.location.href,
                    pageTitle: document.title,
                    detectedHost: window.location.hostname,
                    detectedPersonId: detectedWebKitPersonId(),
                    expectedPersonId: KALVIAN_ROOTS_WEBKIT_EXPECTED_PERSON_ID || KALVIAN_ROOTS_WEBKIT_PERSON_ID,
                    isFamilySearchPage: /(^|\\.)familysearch\\.org$/i.test(window.location.hostname),
                    isPersonDetailsPage: /\\/tree\\/person\\/details\\//i.test(window.location.pathname),
                    debugNotes: notes
                };
            }

            \(extractorScript)

            if (!KALVIAN_ROOTS_WEBKIT_PERSON_ID) {
                postWebKitExtractionResult({
                    sourcePersonId: '',
                    parentFamilySearchId: null,
                    extractedAt: new Date().toISOString(),
                    sourceUrl: window.location.href,
                    children: [],
                    spouseGroups: [],
                    status: 'wrongPage',
                    failureReason: 'Open a FamilySearch person Details page before extracting.',
                    url: window.location.href,
                    pageTitle: document.title,
                    detectedHost: window.location.hostname,
                    detectedPersonId: null,
                    expectedPersonId: KALVIAN_ROOTS_WEBKIT_EXPECTED_PERSON_ID || null,
                    isFamilySearchPage: window.location.hostname === 'www.familysearch.org',
                    isPersonDetailsPage: /\\/tree\\/person\\/details\\//i.test(window.location.pathname),
                    debugNotes: ['FamilySearch WebKit extraction did not find a person ID in the current page URL']
                });
                return 'missing-person-id';
            }

            window.setTimeout(function () {
                postWebKitExtractionResult(makeWebKitFailureResult(
                    'extractorTimeout',
                    'FamilySearch extraction timed out after ' + Math.round(KALVIAN_ROOTS_WEBKIT_TIMEOUT_MS / 1000) + ' seconds.',
                    [
                        'FamilySearch WebKit extraction timed out before the extractor returned a result',
                        'FamilySearch extraction stage at timeout: ' + webKitExtractionStage()
                    ]
                ));
            }, KALVIAN_ROOTS_WEBKIT_TIMEOUT_MS);

            window.extractFamilySearchChildren(KALVIAN_ROOTS_WEBKIT_PERSON_ID)
                .then(postWebKitExtractionResult)
                .catch(error => {
                    postWebKitExtractionResult(makeWebKitFailureResult(
                        'extractorError',
                        cleanWebKitMessage(error && error.message),
                        [
                            'FamilySearch WebKit extraction failed before result callback',
                            'FamilySearch extraction stage at failure: ' + webKitExtractionStage()
                        ]
                    ));
                });

            return 'started';
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
