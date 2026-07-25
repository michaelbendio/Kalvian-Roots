#!/usr/bin/env python3

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

from search_child import (
    clean_line,
    collect_child_groups,
    default_roots_path,
    extract_given_name,
    extract_first_name_from_person_line,
    iter_families,
    normalize_exact_token,
    parse_child_entries,
)


SPOUSE_PREFIX_WORDS = {
    "ent",
    "leski",
    "n",
    "sot",
}
WORD_RE = re.compile(r"[A-Za-zÅÄÖåäö][A-Za-zÅÄÖåäö.\-]*")


@dataclass
class Match:
    family_id: str
    relationship: str
    couple_lines: list[str]
    family_lines: list[str]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Find Juuret Kälviällä parent couples and married children by "
            "the spouses' given names. Name order does not matter."
        )
    )
    parser.add_argument("given_name_1", help="One spouse's given name")
    parser.add_argument("given_name_2", help="The other spouse's given name")
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
        help="Print the whole matching family block after each result",
    )
    return parser.parse_args()


def names_match_pair(
    first_name: str,
    second_name: str,
    requested_first: str,
    requested_second: str,
) -> bool:
    first = normalize_exact_token(first_name)
    second = normalize_exact_token(second_name)
    query_first = normalize_exact_token(requested_first)
    query_second = normalize_exact_token(requested_second)
    return (
        first == query_first and second == query_second
    ) or (
        first == query_second and second == query_first
    )


def extract_parent_lines(family_lines: list[str]) -> list[str]:
    parent_lines: list[str] = []

    for line in family_lines[1:]:
        stripped = line.strip()
        if stripped.startswith("Lapset"):
            break
        if not stripped.startswith("★"):
            continue
        if extract_first_name_from_person_line(stripped):
            parent_lines.append(clean_line(stripped))
        if len(parent_lines) == 2:
            break

    return parent_lines


def extract_spouse_given_name(entry: str) -> str | None:
    _, separator, spouse_text = entry.partition("∞")
    if not separator:
        return None

    for match in WORD_RE.finditer(spouse_text):
        word = match.group(0).rstrip(".")
        if normalize_exact_token(word) in SPOUSE_PREFIX_WORDS:
            continue
        return word
    return None


def find_matches(text: str, given_name_1: str, given_name_2: str) -> list[Match]:
    matches: list[Match] = []

    for family_lines in iter_families(text):
        family_id = family_lines[0].split(",", 1)[0].strip()
        parent_lines = extract_parent_lines(family_lines)

        if len(parent_lines) == 2:
            first_parent = extract_first_name_from_person_line(parent_lines[0])
            second_parent = extract_first_name_from_person_line(parent_lines[1])
            if (
                first_parent
                and second_parent
                and names_match_pair(
                    first_parent,
                    second_parent,
                    given_name_1,
                    given_name_2,
                )
            ):
                matches.append(
                    Match(
                        family_id=family_id,
                        relationship="Parents",
                        couple_lines=parent_lines,
                        family_lines=family_lines,
                    )
                )

        for group in collect_child_groups(family_lines):
            for entry in parse_child_entries(group):
                child_name = extract_given_name(entry)
                spouse_name = extract_spouse_given_name(entry)
                if (
                    child_name
                    and spouse_name
                    and names_match_pair(
                        child_name,
                        spouse_name,
                        given_name_1,
                        given_name_2,
                    )
                ):
                    matches.append(
                        Match(
                            family_id=family_id,
                            relationship="Married child",
                            couple_lines=[entry],
                            family_lines=family_lines,
                        )
                    )

    return matches


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parent
    roots_path = (
        args.roots_file.expanduser()
        if args.roots_file
        else default_roots_path(repo_root)
    )

    if not roots_path.exists():
        print(f"Roots file not found: {roots_path}", file=sys.stderr)
        return 1

    text = roots_path.read_text(encoding="utf-8")
    matches = find_matches(text, args.given_name_1, args.given_name_2)
    total_matches = len(matches)

    if args.max_results > 0:
        matches = matches[: args.max_results]

    query = f"{args.given_name_1} + {args.given_name_2}"
    if not matches:
        print(f"No matching couples found for {query}.")
        return 0

    if args.max_results > 0 and total_matches > len(matches):
        print(
            f"Found {total_matches} matching couples for {query}. "
            f"Showing first {len(matches)}."
        )
    else:
        print(f"Found {total_matches} matching couples for {query}.")
    print()

    for match in matches:
        print(match.family_id)
        print(f"  {match.relationship}:")
        for line in match.couple_lines:
            print(f"    {line}")
        if args.show_family:
            print("  Family:")
            for line in match.family_lines:
                print(f"    {line}")
        print()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
