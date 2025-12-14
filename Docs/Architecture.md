## Kalvian Roots Architecture

### Overview
- **App coordinator**: `JuuretApp` (state, orchestration, dependency wiring)
- **UI**: SwiftUI views (`ContentView`, `JuuretView`, `AISettingsView`, etc.) using `@Environment(JuuretApp.self)`
- **Models**: `Family`, `Person`, `EventType`
- **Core services**: `AIParsingService`, `FamilyResolver`, `NameEquivalenceManager`
- **Utilities**: `FileManager` (canonical file I/O), `DebugLogger`, `FamilyIDs`, font helpers

### Data flow
1) User loads `JuuretKälviällä.roots` via `FileManager` or auto-loads from canonical location
2) `JuuretApp.extractFamily(familyId:)` extracts the family text from the file
3) `AIParsingService` calls current `AIService` to parse into JSON
4) JSON is cleaned and decoded into `Family`
5) UI displays `Family`; optional cross-references via `FamilyResolver`

### App coordinator
- `JuuretApp` owns: `AIParsingService`, `FamilyResolver`, `NameEquivalenceManager`, app `FileManager`
- Provides operations: load file, extract family, switch/configure AI service, generate citations/Hiski URLs

### AI parsing
- `AIService` protocol: `name`, `isConfigured`, `configure(apiKey:)`, `parseFamily(familyId:familyText:) -> String` (JSON)
- `AIParsingService` selects default service via `AIServiceFactory` / `PlatformAwareServiceManager`
- JSON schema (top-level keys):
  - `familyId`, `pageReferences`, `father`, `mother`, `additionalSpouses`, `children`, `notes`, `childrenDiedInfancy`
  - `Person` fields include: `name`, `patronymic?`, `birthDate?`, `deathDate?`, `marriageDate?`, `spouse?`, `asChildReference?`, `asParentReference?`, `familySearchId?`, `noteMarkers` and enhancement fields

### File I/O
- Canonical file: `JuuretKälviällä.roots` in the app’s Documents (user-accessible via iCloud Drive symlink)
- `FileManager` handles opening via `NSOpenPanel` on macOS and reading content, recent files, and extracting per-family text

### Cross-references (planned/partial)
- `FamilyResolver` resolves `{FAMILY_ID}` links and birth-date-based matches to build a `FamilyNetwork`
- `NameEquivalenceManager` learns Finnish name equivalences (e.g., Liisa ↔ Elisabet)

### Citations and Hiski
- `EnhancedCitationGenerator` formats readable citations
- `HiskiQuery` builds structured URLs for church records (birth, death, marriage, baptism, burial)

### Logging and diagnostics
- `DebugLogger` with levels/categories, timers, and structured messages
- AI calls and JSON parsing steps are timed and logged

### UI patterns
- Mac: `NavigationSplitView` with sidebar (status, tools)
- iOS: `NavigationView`
- Fonts: `Font+Genealogy.swift` for larger, readable typography

### Notes
- API keys stored in `UserDefaults` for personal use (consider Keychain for production)
- Guard macOS-only code (e.g., `NSOpenPanel`) with `#if os(macOS)` if targeting iOS


## Design and Citation Guidelines

### Devices and purpose
- Personal app used across three devices: M4 Pro Mac mini (64 GB RAM, 1 TB), M4 iPad Pro, iPhone 16 Pro Max (512 GB).
- Purpose: Provide citations for persons in FamilySearch.

### What is a citation in this context?
- Citations are verifiable evidence for life events (birth, marriage, death).
- In FamilySearch, citations:
  1. Provide evidence for assertions about life events
  2. Help minimize duplicate effort
  3. Provide sources for finding additional information about a family

### Citation sources used by Kalvian Roots
1. Juuret Kälviällä (Kalvian Roots): a Finnish genealogy book with 1,600+ families and 18,000+ lines of text.
2. Hiski (`hiski.genealogia.fi`): Historical church record database by the Genealogical Society of Finland.

### Are citations trustworthy?
Juuret Kälviällä (by Uuno Huhtala) primarily sources from:
1. Church Records: Kälviä and Ullava parish registers (birth, marriage, death, baptismal, burial)
2. Archival Documents: National/Regional archives (land records, tax rolls, court documents)
3. Microfilm Collections: Many records were consulted via microfilm (now often digitized)
4. Local Histories: Village/household histories and earlier publications
5. Community Contributions: Local residents and Kälviä Historical Society (publisher)

Hiski caveat: Entries can reflect errors from original clergy entries, “black books” copy processes, or later data entry. Use critically and verify with primary sources.

Conclusion: Each source can contain human error, but they are valid evidence for asserting life events.

### Symbols used in Juuret Kälviällä
- ★ birth (often begins a family member’s line; birth date may be absent)
- n about (e.g., `n 1693` → about 1693)
- ∞ marriage (followed by a marriage date)
- † death (if present, followed by a death date)
- *) note (matching symbol after last child contains the note)
- **) second note

### Family structure and IDs
- Families contain: family ID with page number(s), parents, children, additional spouses and their children; delimited by blank lines.
- Family ID: one/two-word clan name + digit(s) or roman numeral (I–IV) + digit(s).
- The app maintains a set of valid family IDs; parsed IDs should be validated against this set.
- Examples: `VÄHÄ-HYYPPÄ 7`, `MAUNUMÄKI IV 5`, `PIENI SIKALA 3`.
- Family IDs in caps with page numbers begin a new family. `as_child` and `as_parent` references are family IDs in lower case.

### Dates, names, FamilySearch IDs
- Dates: `dd.mm.yyyy` or year-only `yyyy`. Short marriage dates: `yy`. Approximate: `n yyyy`.
- Names: given name or given + abbreviated patronymic or clan name.
- FamilySearch IDs: `<ABCD-123>` (4 chars, hyphen, 3 chars) may follow any name; added during processing.

### Line formats
- Parents’ lines:
  - `★ birth date | name | {as_child family ID} | † death date`
- Children’s header: line beginning with `Lapset`
- Children’s lines:
  - `★ birth date | given name | ∞ date | spouse name | as_parent family ID`
- Additional spouses: `II` or `III puoliso`
  - `★ birth date | name | ∞ date | as_child family ID`
- Children of additional spouses follow a `Lapset` line; notes follow last child.

### Reference semantics
- `as_child` families: where the parents (or a child’s spouse) appear as children.
- `as_parent` families: where the children and their spouses appear as parents. Important for death dates, full 8‑digit marriage dates, and spouse birth/family ID.

### Finding references
- Finding `as_child` family:
  - If family ID present → open that family, then search for: birth date match, name match, spouse name match (or variant). If any match, it’s the right family.
  - If no family ID or no matches → search by birth date; check spouse name/variant and marriage year (last 2 digits). If either match, accept; otherwise stop for manual review.
- Finding `as_parent` family (married children only):
  - If family ID present → open that family; check birth date, spouse (or variant), marriage year (last 2 digits). If any match, accept.
  - If not present/match → search birth date; check spouse name/variant and marriage year (last 2 digits). If either match, accept.

### Family web
- The “family web” = nuclear parents + their children + all referenced `as_child` and `as_parent` families.

### Example families and citations

HYYPPÄ 6 (nuclear):
```
HYYPPÄ 6, page 370
★ 09.10.1726 	Jaakko Jaakonp. {Hyyppä 5} 									† 07.03.1789
★ 02.03.1733 	Maria Jaakont. {Pietilä 7}									† 18.04.1753
∞ 08.10.1752.
II puoliso
★ 11.01.1732 1. Brita Eliant. Tikkanen 5, Matti Nurilan leski 			† 31.03.1767
∞ 06.10.1754.
Lapset
★ 27.03.1763	Maria <L44K-3G9>		∞ 82 Matti Korpi <L44K-3VH>		Korpi 9
★ 11.02.1766	Brita			∞ 86 Henrik Karhulahti					Iso-Hyyppä 10
III puoliso
★ 20.01.1744	Kaarin Juhont. Kourijärvi									† 01.05.1793
∞ 1768
Lapset
★ 29.09.1773	Liisa			naimaton 								† 28.04.1861
★ 21.09.1779	Malin			∞ 06 Juho Koivusuonniemi					Koivusuonniemi 2
★ 31.07.1787	Juho			∞ 08 Brita Mikkola						Hyyppä 11
Maria kuoli 1784 ja lapsi samana vuonna.
```

Citation for HYYPPÄ 6 (nuclear):
```
Information on page 370 includes:
Jaako Jaakonp., 9 October 1726 - 7 March 1789
Maria Jaakont., 2 March 1733 - 18 April 1753
Married 8 October 1752
Additional spouse:
Brita Eliant., 11 January 1732 - 31 March 1767
Married 6 October 1754
Children:
Maria, 27 March 1763 - 28 July 1784, m: 8 October 1782 to Matti Korpi
    [8-digit marriage and death dates found in as_parent family, Korpi 9, included below. Ignore FamilySearch IDs]
Brita, 11 February 1766 - 10 April 1796, m. 4 November 1786 to Henrik Pietarinp.
    [as above, applies to married children where an as_parent family actually exists.]
Additional spouse:
Kaarin Juhont. Kourijärvi, 20 January 1744 - 1 May 1793
Married 1768
Children:
Liisa, 29 September 1773 - 28 April 1861, unmarried
Malin, 21 September 1779, m. Juho Koivusuonniemi 1806
    [Koivusuonniemi 2 is missing in the Juuret Kälviällä text.]
Juho, 31 July 1787 - 5 June 1831, m. Brita Erikint 18 December 1808
Notes:
Maria kuoli 1784 ja lapsi samana vuonna.
Parents:
Jaako Jaakonp.'s parents' family is on page 369
Maria Jaakont.'s parents' family is on page 457
Children:
Maria's death and marriage dates are on page 107
Brita's death and marriage dates are on pages 371,372
Juho's death and marriage dates are on page 372
```

HYYPPÄ 5 (Jaakko’s as_child):
```
HYYPPÄ 5, page 369 [Jaakko Jaakonp.'s as_child family]
★ 11.07.1698	Jaakko Jaakonp. <KLV2-Q9B> {Hyyppä 4} 							† 31.08.1735
★ 16.10.1700	Malin Matint. <KLV2-3ZG> {Passoja 3}							† 10.08.1771
∞ 30.11.1724.
Lapset
★ 09.10.1726	Jaakko			∞ 52 Maria Pietilä					Hyyppä 6
★ 08.10.1727	Malin <GLCP-G9P>		∞ 52 sot. Juho Stenbäck				Koivusalo 3
★ 30.09.1728	Anna			∞ 73 Matti Niilonp.						lapsettomia
★ 15.03.1730	Niilo			∞ 52 Malin Kourijärvi					Iso-Hyyppä 7
★ 23.03.1733	Maria <M8Z2-FBC>		∞ 50 Juho Valkamaa <M88S-N6G>			Lassila 9
II puoliso
★ 1689		renki Erik Jaakonp., synt. Limingassa							† 28.08.1778
∞ 01.08.1736.
Lapset
★ 22.01.1737	Brita			∞ 56 Niilo Pernu						Pernu 11
★ 26.07.1738	Abraham
Lapsena kuollut 6.
```

Citation (as_child style):
```
Information of page 369 includes:
Jaakko Jaakonp., 11 July 1698 - 31 August 1735
Malin Matint., 16 October 1700 - 10 August 1771
Married 30 November 1724
Children
Jaakko, b. 9 October 1726, m. Maria Pietila 1752
    [don't follow as_parent references for as_child families, just state birth date]
Malin, b. 8 October 1727, m. Juho Stenbäck 1752
    [infer 4-digit years from short dates; ignore lower-case words like "sot."]
Anna, b. 30 September 1728, m. Matti Niilonp. 1773
Niilo, b. 15 March 1730, m. Malin Kourijärvi 1752
Maria, b. 23.03.1733, m. Juho Valkamaa 1750
Additional spouse:
Erik Jaakonp., 1689 - 28 August 1778
Married 1 August 1736
Children:
Brita, b. 22 January 1737, m. Niilo Pernu 1756
Abraham, b 26 July 1738
Notes:
6 children died as infants.
```

PIETILÄ 7 (Maria’s as_child):
```
PIETILÄ 7, page 457 [Maria Jaakont.'s as_child family]
★ 19.07.1707	Jaakko Jaakonp. {Pietilä 5}	                            † 17.02.1792
★ 27.08.1701	Brita Jaakont. Manninen	                                † 20.12.1776
∞ 17.11.1728.
Lapset
★ 30.10.1730	Elisabet	    ∞ 49 Antti Suonperä	                    Suonperä III 1
★ 02.03.1733	Maria	        ∞ 52 Jaakko Hyyppä	                    Hyyppä 6
★ 19.04.1735	Matti	        ∞ 54 Maria Pentint.	                    Pietilä 10
★ 11.05 1737	Erik
★ 13.10.1743	Antti	        ∞ 62 Maria Ek	                        Pietilä 11
Lapsena kuollut 3.
```

TIKKANEN 5 (Brita’s as_child):
```
TIKKANEN 5, pages 239,240 [Brita Eliant.'s as_child family]
★ 1708 			Elias Juhonp. Tikkanen <LHCZ-6X5> synt. Veteli			    † 28.08.1777
∞ 17.12.1705 	Elisabet Pietarint. <LHCZ-X2F> {Karhulahti 3} 				† 29.10.1757
Lapset
★ 20.12.1729 	Anna <GDWM-MWB>			∞ 51 Pietari Peitso <9DS5-XMW>			I-Peitso III 1
★ 19.01.1732 	Brita <MP1R-H18>		∞ 50 Matti Nurila <M8ZJ-SNT>			Nurila 6
★ 24.03.1734 	Johannes <GDWM-31H>		∞ 53 Beata Jaakont. <G11L-Y8S>			Tikkanen 7
★ 30.01.1736 	Maria <GS2K-5Z1>		∞ 56 Erik Korpijärvi <LHCH-31K>			Korpijärvi 7b
★ 05.12.1741 	Elisabet <LHVH-DJ3>		∞ Matti Juhonp. <GD75-NH9>				Tikkanen 9
★ 05.09.1743	Magdalena <LRDS-4R2>	∞ 68 Elias Järvi <GQVH-CRX>				Järvi 10
★ 02.02.1745	Matti <KJ47-8XH>		∞ 67 Kaarin Pernu <G11G-DJM>				Tikkanen 8
★ 15.05.1751	Elias <GDW9-ZG1>		∞ 74 Susanna Juhont <G11G-NFV>			Tikkanen 10
II puoliso
★ 1726 			1. Maria Henrikint. <GS17-LWY> synt. Lohtaja				† 09.04.1797
∞ 22.10.1760.
Lapset
★ 12.05.1763 	Katariina <KCG3-393>	∞ 85 Mikko Kykyri <9NWF-9RJ>			Kykyri II 6
★ 28.11.1767 	Antti <M887-TVF>										-87 Lohtaja
Lapsena kuollut 8.
```

KORPI 9 (as_parent for Maria and Matti):
```
KORPI 9, eli Seppä page 107 [Maria and Matti's as_parent family]
    [We don't make a citation for this family, just retrieve the death and marriage dates and add them to their nuclear family citation.]
★ 10.06.1759    Matti Joonanp. <L44K-3VH> {Korpi 8}                             † 26.08.1808
★ 27.03 1763    Maria Jaakont. <L44K-3G9> {Iso-Hyyppä 6}                        † 28.07.1784
∞ 08.11.1782.
II puoliso
★ 22.06.1768    Brita Juhont. <L44V-K5R> Apellöf Tikanoja 2                     † 27.06.1792
∞ 02.05.1790.
Lapset
★ 08.02.1791    Juho <KL7C-WM2>         ∞ 28.10.10 Liisa Vähälä <L4H3-VJB>      Korpi
III puoliso
★ 02.11.1762    Liisa Joonant. <LRKS-2FF> Mutka
∞ 19.06.1803.
Lapset
★ 26.05.1804    Maria <LD1F-DSZ>        ∞ 22.06.26 Antti Räf <L44K-S6H>         Kaustinen
```

ISO-HYYPPÄ 10 (as_parent for Brita and Matti):
```
ISO-HYYPPÄ 10, page 371,372 [Brita and Matti's as_parent family]
    [Again, just get the death and marriage dates]
★ 21.11.1758 	Henrik Pietarinp. {Karhulahti III 1}                    † 22.12.1815
★ 11.02.1766 	Brita Jaakont. {Iso-Hyyppä 6}                           † 10.04.1796
∞ 04.11.1786.
Lapset
★ 14.12.1789 	Erik                                                    † 08.01.1890
II puoliso
★ 01.10.1774 	Brita Juhont. <GMC4-GTT> Hangaskangas 9						† 13.10.1844
∞ 23.06.1797.
Lapset
★ 05.01.1803 	Erik			∞ Sofia Ahola							Hyyppä
Lapsena kuollut 2.
```

ISO-HYYPPÄ 11 (as_parent for Juho and Brita):
```
ISO-HYYPPÄ 11, page 372 [Juho and Brita's as parent family]
    [When the family IDs don't match, fall back to searching for, e.g. Juho's birth date].  
★ 31.07.1787 	Juho Jaakonp. {Iso-Hyyppä 6}							† 05.06.1831
★ 19.03.1784 	Brita Erikint. {Mikkola 12}
∞ 18.12.1808.
Lapset
★ 09.06.1810 	Kaisa Liisa
★ 17.08.1812 	Maria
★ 28.04.1817 	Brita Magdaleena
Muuttivat 09.07.1822 Kannukseen.
```

Children’s spouses’ as_child families (examples):
```
KORPI 8, eli Seppä pages 106, 107 [Maria's (27.03.1763) husband Matti]
    [The first line of a family is only family ID and page[s] numbers--ignore eli Seppä] 
★ 20.09.1735	Joonas Erikinp. <L9G8-HVZ> {Korpi 5}	                        † 10.01.1806
★ 30.12.1739	Maria Paavalint. <LHCZ-D2R> {Haapaniemi 3}	                    † 28.04.1814
∞ 28.11.1756.
Lapset
★ 10.06.1759	Matti <L44K-3VH>        ∞ 82 Maria Iso-Hyyppä <L44K-3G9>        Korpi 9
★ 15.07.1760	Johannes <GMX7-244>	    ∞ 83 Kaarin Kinnari	<M8ZR-MZX>          Korpi 10
★ 19.03.1764	Katariina <K2ST-M7H>    ∞ 82 Jeremia Siirilä <K2ST-MQF>         Siirilä 8
★ 23.02.1767	Joonas <LHCZ-DZ2>       ∞ 00 Anna Haapaniemi <M8ZY-HMG>         Korpi 12
★ 24.09.1768	Maria <K2YX-YVM>        ∞ 88 Iisak Länttä <K2YX-YJV>            Sikala 8
★ 08.10.1770	Liisa <K2VH-QKK>        ∞ 93 Matti Kourijärvi <M8ZN-7QW>        Kourijärvi 11
★ 13.12.1771	Israel <K2VH-QTH>       ∞ 96 Liisa Haapaniemi <LHHD-1N6>        Korpi 11
★ 16.01.1775    Eeva Kristiina <LHQM-VDY> ∞ 96 Matti Haapala <LHQM-JHB>         Haapala II 2
★ 24.02.1777 	Malin <K2VH-7DY>
★ 14.05.1779	Susanna	<LX33-X8D>      ∞ 02 Erik Videnoja <KJJH-2KT>           Videnoja 9
★ 02.02.1783	Anna Margeta <GDCY-M13>	∞ 08 Juho Vähälä <GDCT-NRZ>             Vähälä II 6
```

KARHULAHTI III 1 (as_child for Henrik):
```
KARHULAHTI III 1, pages 447,448 [Brita's (11.02.1766) husband Henrik]
★ 1728	        Pietari Pietarinp. {Karhulahti 8}                       † 22.06.1808
★ 07.02.1734	Maria Antint. {Herronen 7}	                            † 03.06.1775
∞ 14.11.1751.
Lapset
★ 21.06.1754	Elisabet	    ∞ 79 Erik Lento	                        Lohtaja
★ 25.05.1757	Erik	        ∞ 91 Liisa Järvi	                    K-lahti III 5
★ 21.11.175	    Henrik          ∞ 86 Brita Iso-Hyyppä	                Iso-Hyyppä 10
★ 15.12.1761	Brita	        ∞ 85 1. Juho Mikkola	                Mikkola 10
★ 21.10.1764	Maria	        ∞ 02 1. Antti Suonperä	                Suonperä II 6
★ 19.11.1766	Pietari	        ∞ 91 Kreeta Hakunti	                    K-lahti III 4
★ 24.11.1769	Matti	        ∞ 07 Liisa Pietilä	                    Pietilä II 4
II puoliso
★ 08.06.1734    1. Anna Olavint. Passeja 5, Lauri Nurilan leski         † 03.07.1808
∞ 09.07.1780.
Lapsena kuollut 3.
```

MIKKOLA 12 (as_child for Brita):
```
MIKKOLA 12, page 375 [Juho's (31.07.1787) wife Brita]
★ 09.04.1753	Erik Matinp. Fordell								† 04.11.1826
★ 26.01.1757	Liisa Juhont. Kankkonen							† 30.03.1838
∞ 03.11.1780.	Tulivat Kokkolasta 30.06.1806.
Lapset
★ 21.02.1781	Juho				∞ 06 Liisa Hannila						Mikkola 13
★ 19.03.1784	Brita				∞ 08 Juho Iso-Hyyppä					Hyyppä 11
★ 29.02.1788	Kustaa				∞ 04.11.10 Maria Iso-Hyyppä				Mikkola
★ 19.10.1791	Erik				∞ 26.11.21 Anna Rajaluoto				Mikkolan t.
★ 27.04.1794	Maria				∞ 01.11.13 Juho Broända					Alaveteli
Lapsena kuollut 3.
```

### How the app will be used
- Specify the family ID to work with.
- App shows the family as in Juuret Kälviällä.
- App prompts the selected AI to create standardized JSON for each family in the family web.
- App populates Swift structs and generates citations per person, linking citations to names.
- If citation creation fails, the app alerts for manual citation; the manual citation is saved and associated with the person. Clicking a name shows the citation and copies it to the clipboard.

### Roadmap
- Add Hiski citations.
- Build a bespoke browser/automation to add citations to FamilySearch.
- First milestone: get citations working.

