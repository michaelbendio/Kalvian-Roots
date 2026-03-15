#!/usr/bin/env python3

from __future__ import annotations

import argparse
import re
import sys
import unicodedata
from dataclasses import dataclass
from pathlib import Path


HEADER_RE = re.compile(r"^[A-ZÅÄÖ0-9./ -]+(?:,.*)?\bpage(?:s)?\b")
DATE_RE = r"(?:n\s+\d{4}|\d{1,2}\.\d{1,2}\.\d{4}|\d{4})"
PERSON_LINE_RE = re.compile(
    rf"^★\s*(?:{DATE_RE})?\s*([A-Za-zÅÄÖåäö.\-]+)"
)
PATRONYMIC_SUFFIXES = (
    "inpoika",
    "intytar",
    "pojka",
    "dotter",
    "sson",
    "poik",
    "tytar",
    "son",
    "dtr",
    "inp",
    "int",
    "po",
    "ty",
    "p",
    "t",
)

NAME_VARIANTS = {
    "aabraham": {"abram", "abraham", "abrahammus"},
    "aaron": {"aron", "aaron"},
    "agneta": {"agneta", "agnete", "aune"},
    "anna": {"anna", "anne", "arna", "annika"},
    "antti": {"anders", "andreas", "andrej"},
    "brita": {"briita", "brigitta", "brit", "bridget"},
    "catharina": {"katariina", "kaarin", "kaarina", "katarina", "carin", "karin"},
    "david": {"dawid", "taavetti"},
    "eerik": {"eerik", "erik", "eric", "erich"},
    "elias": {"elijs", "elis"},
    "elisabet": {"elisabet", "elisabeth", "lisa", "liisa", "betta", "elisabeta"},
    "elin": {"elena", "elina", "helen"},
    "eva": {"eeva"},
    "gabriel": {"gabril"},
    "greta": {"kreta", "kreeta", "margareta", "margeta", "magareta", "margaretha"},
    "gustaf": {"kustaa", "kusataa", "gustav"},
    "helena": {"helena", "helga", "elena"},
    "henrik": {"henrik", "hendrich", "heikki"},
    "jaakko": {"jacob", "jakob", "jacobus", "jaako", "jacop"},
    "jean": {"johan", "johannes", "johanne", "juho", "jons", "hans"},
    "johanna": {"johana"},
    "juho": {"johan", "johannes", "johann"},
    "kalle": {"carl", "karl"},
    "kristian": {"christian", "kristian"},
    "kristina": {"kristiina", "christina", "stiina", "stina"},
    "lauri": {"lars", "laurentius", "laurent"},
    "liisa": {"elisabet", "lisa", "elisabeth"},
    "magdalena": {"magdaleena", "malin", "malen", "malena"},
    "maria": {"maria", "marie", "marja"},
    "markus": {"marcus", "marx"},
    "martti": {"martin", "martinus", "marten"},
    "matias": {"mathias", "matthias", "mats", "matts", "matti", "matin"},
    "mikael": {"mickel", "michel", "mikko"},
    "niilo": {"nicolaus", "nils", "niklas"},
    "olavi": {"olof", "olaus", "ole"},
    "paavali": {"paul", "pauli", "pahl", "pal"},
    "petteri": {"petter", "peter", "pietari", "petrus"},
    "sakari": {"sakarias", "zacharias"},
    "simo": {"simon", "simen"},
    "sofia": {"sofia", "sophie"},
    "susanna": {"susana", "susanne"},
    "tuomas": {"thomas", "tomas"},
}

CANONICAL_NAME_BY_ALIAS: dict[str, str] = {}
ALL_VARIANTS_BY_CANONICAL: dict[str, set[str]] = {}
for canonical, variants in NAME_VARIANTS.items():
    alias_set = {canonical, *variants}
    normalized_aliases = set()
    for alias in alias_set:
        normalized = alias.lower()
        normalized_aliases.add(normalized)
        CANONICAL_NAME_BY_ALIAS[normalized] = canonical
    ALL_VARIANTS_BY_CANONICAL[canonical] = normalized_aliases


@dataclass
class Match:
    family_id: str
    father_line: str
    child_entries: list[str]
    family_lines: list[str]


def strip_diacritics(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value)
    return "".join(char for char in normalized if not unicodedata.combining(char))


def squash_whitespace(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip()


def normalize_exact_token(value: str) -> str:
    value = strip_diacritics(value).lower()
    value = re.sub(r"[^a-z]", "", value)
    return value


def normalize_name_token(value: str) -> str:
    value = normalize_exact_token(value)
    return CANONICAL_NAME_BY_ALIAS.get(value, value)


def clean_line(value: str) -> str:
    value = re.sub(r"<[^>]+>", "", value)
    value = re.sub(r"\{[^}]+\}", "", value)
    return squash_whitespace(value)


def default_roots_path(repo_root: Path) -> Path:
    jk_location = repo_root / "JKlocation.txt"
    if jk_location.exists():
        raw_path = jk_location.read_text(encoding="utf-8").strip()
        if raw_path:
            return Path(raw_path).expanduser()
    return (
        Path.home()
        / "Library/Mobile Documents/iCloud~com~michael-bendio~Kalvian-Roots/Documents/JuuretKälviällä.roots"
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Search Juuret Kälviällä families by a child's given name and patronymic. "
            "Examples: Juho Erikinpoika, Brita Erikint."
        )
    )
    parser.add_argument("given_name", help="Child given name, for example Juho")
    parser.add_argument("patronymic", help="Child patronymic, for example Erikinpoika")
    parser.add_argument(
        "--roots-file",
        type=Path,
        help="Override the default JuuretKälviällä.roots path",
    )
    parser.add_argument(
        "--max-results",
        type=int,
        default=0,
        help="Limit the number of results shown",
    )
    parser.add_argument(
        "--show-family",
        action="store_true",
        help="Print the whole matching family block after each summary",
    )
    return parser.parse_args()


def iter_families(text: str) -> list[list[str]]:
    families: list[list[str]] = []
    current: list[str] = []

    for raw_line in text.splitlines()[2:]:
        if HEADER_RE.match(raw_line):
            if current:
                families.append(current)
            current = [raw_line]
            continue
        if current:
            current.append(raw_line)

    if current:
        families.append(current)
    return families


def extract_first_name_from_person_line(line: str) -> str | None:
    match = PERSON_LINE_RE.match(clean_line(line))
    if not match:
        return None
    return match.group(1)


def patronymic_prefix(patronymic: str) -> str:
    value = strip_diacritics(patronymic).lower()
    value = re.sub(r"[^a-z]", "", value)

    for suffix in PATRONYMIC_SUFFIXES:
        if value.endswith(suffix):
            value = value[: -len(suffix)]
            break

    return value


def possible_patronymic_prefixes(name: str) -> set[str]:
    normalized = normalize_name_token(name)
    variants = ALL_VARIANTS_BY_CANONICAL.get(normalized, {normalized})
    prefixes: set[str] = set()

    for variant in variants:
        if not variant:
            continue
        prefixes.add(variant)
        if variant.endswith("i") and len(variant) > 1:
            prefixes.add(variant[:-1] + "in")
        else:
            prefixes.add(variant + "n")
            prefixes.add(variant + "in")

    return prefixes


def father_matches_patronymic(father_name: str, patronymic: str) -> bool:
    prefix = patronymic_prefix(patronymic)
    if not prefix:
        return False
    return prefix in possible_patronymic_prefixes(father_name)


def collect_child_groups(family_lines: list[str]) -> list[list[str]]:
    groups: list[list[str]] = []
    current_group: list[str] = []
    in_children_section = False

    for line in family_lines[1:]:
        stripped = line.strip()

        if stripped.startswith("Lapset"):
            in_children_section = True
            if current_group:
                groups.append(current_group)
                current_group = []
            continue

        if "puoliso" in stripped or HEADER_RE.match(stripped):
            in_children_section = False
            if current_group:
                groups.append(current_group)
                current_group = []
            continue

        if not in_children_section:
            continue

        if not stripped:
            if current_group:
                groups.append(current_group)
                current_group = []
            continue

        if stripped.startswith("★"):
            if current_group:
                groups.append(current_group)
            current_group = [stripped]
            continue

        if current_group and re.match(rf"^{DATE_RE}\b", stripped):
            current_group.append(stripped)
            continue

        if current_group:
            groups.append(current_group)
            current_group = []

    if current_group:
        groups.append(current_group)

    return groups


def extract_given_name(entry: str) -> str | None:
    match = PERSON_LINE_RE.match(entry)
    if not match:
        return None
    return match.group(1)


def parse_child_entries(group_lines: list[str]) -> list[str]:
    group_text = clean_line(" ".join(group_lines))
    if not group_text:
        return []

    if "∞" in group_text:
        return [group_text]

    entries: list[str] = []
    for match in re.finditer(
        rf"(?:^|★|,)\s*((?:{DATE_RE})?\s*[A-Za-zÅÄÖåäö][^,]*)",
        group_text,
    ):
        entry = squash_whitespace(match.group(1)).rstrip(".")
        if entry:
            entries.append(f"★ {entry}")
    return entries


def find_matches(text: str, given_name: str, patronymic: str) -> list[Match]:
    requested_name = normalize_exact_token(given_name)
    matches: list[Match] = []

    for family_lines in iter_families(text):
        father_line = ""
        father_name = None

        for line in family_lines[1:]:
            stripped = line.strip()
            if stripped.startswith("★"):
                father_line = clean_line(stripped)
                father_name = extract_first_name_from_person_line(stripped)
                break

        if not father_name or not father_matches_patronymic(father_name, patronymic):
            continue

        matching_child_entries: list[str] = []
        for group in collect_child_groups(family_lines):
            for entry in parse_child_entries(group):
                child_name = extract_given_name(entry)
                if child_name and normalize_exact_token(child_name) == requested_name:
                    matching_child_entries.append(entry)

        if not matching_child_entries:
            continue

        family_id = family_lines[0].split(",", 1)[0].strip()
        matches.append(
            Match(
                family_id=family_id,
                father_line=father_line,
                child_entries=matching_child_entries,
                family_lines=family_lines,
            )
        )

    return matches


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parent
    roots_path = args.roots_file.expanduser() if args.roots_file else default_roots_path(repo_root)

    if not roots_path.exists():
        print(f"Roots file not found: {roots_path}", file=sys.stderr)
        return 1

    text = roots_path.read_text(encoding="utf-8")
    matches = find_matches(text, args.given_name, args.patronymic)
    total_matches = len(matches)

    if args.max_results > 0:
        matches = matches[: args.max_results]

    query = f"{args.given_name} {args.patronymic}"
    if not matches:
        print(f"No matching families found for {query}.")
        return 0

    if args.max_results > 0 and total_matches > len(matches):
        print(
            f"Found {total_matches} matching families for {query}. "
            f"Showing first {len(matches)}."
        )
    else:
        print(f"Found {total_matches} matching families for {query}.")
    print()

    for match in matches:
        print(match.family_id)
        print(f"  Father: {match.father_line}")
        for child_entry in match.child_entries:
            print(f"  Child:  {child_entry}")
        if args.show_family:
            print("  Family:")
            for line in match.family_lines:
                print(f"    {line}")
        print()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
