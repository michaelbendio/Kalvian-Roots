#!/usr/bin/env python3
import argparse
import json
import sys
from datetime import datetime


def candidate_line(label, candidate):
    if not candidate:
        return None

    parts = [candidate.get("name")]
    if candidate.get("birthDate"):
        parts.append(candidate["birthDate"])
    if candidate.get("familySearchId"):
        parts.append(candidate["familySearchId"])
    if candidate.get("hiskiCitation"):
        parts.append(candidate["hiskiCitation"])

    return f"{label}: " + ", ".join(part for part in parts if part)


def format_action(action, fallback_action_id=None):
    context = action.get("context") or {}
    lines = []
    lines.append(
        action.get("approvalPrompt")
        or action.get("label")
        or action.get("type")
        or "Action proposal"
    )
    lines.append("")
    lines.append("Action: " + action.get("type", "unknown"))
    lines.append("ID: " + action.get("id", fallback_action_id or ""))

    person_name = action.get("personName")
    person_id = action.get("personId")
    if person_name or person_id:
        person = person_name or "unknown person"
        if person_id:
            person = f"{person} ({person_id})"
        lines.append(f"Person: {person}")

    if context.get("coupleIndex") is not None:
        lines.append("Couple: " + str(context["coupleIndex"] + 1))
    if context.get("status"):
        lines.append("Status: " + context["status"])
    if context.get("birthDate"):
        lines.append("Birth: " + context["birthDate"])

    source_lines = [
        candidate_line("Juuret", context.get("juuret")),
        candidate_line("HisKi", context.get("hiski")),
        candidate_line("FamilySearch", context.get("familySearch")),
    ]
    source_lines = [line for line in source_lines if line]
    if source_lines:
        lines.append("")
        lines.extend(source_lines)

    if action.get("requiresApproval"):
        lines.append("")
        lines.append("Requires explicit approval before changing source data.")

    return "\n".join(lines)


def source_date_variants(iso_date):
    if not iso_date:
        return []

    variants = [iso_date]
    try:
        date = datetime.strptime(iso_date, "%Y-%m-%d")
    except ValueError:
        return variants

    variants.append(f"{date.day}.{date.month}.{date.year}")
    variants.append(f"{date.day:02d}.{date.month:02d}.{date.year}")
    return list(dict.fromkeys(variants))


def matching_source_lines(source_text, action):
    context = action.get("context") or {}
    juuret = context.get("juuret") or {}
    name = (juuret.get("name") or action.get("personName") or "").casefold()
    date_variants = source_date_variants(context.get("birthDate"))

    matches = []
    for index, line in enumerate(source_text.splitlines(), start=1):
        folded = line.casefold()
        has_name = name and name in folded
        has_date = any(variant in line for variant in date_variants)
        if has_name and (has_date or not date_variants):
            matches.append((index, line))

    return matches


def format_source_context_preview(
    action,
    source_text,
    fallback_action_id=None,
    expected_type=None,
    title="Source context preview:",
    wrong_type_message=None,
):
    lines = [format_action(action, fallback_action_id=fallback_action_id)]
    lines.append("")
    lines.append(title)

    if expected_type and action.get("type") != expected_type:
        lines.append(wrong_type_message or f"This action is not {expected_type}.")
        lines.append("No source edit was applied.")
        return "\n".join(lines)

    matches = matching_source_lines(source_text, action)
    if len(matches) == 1:
        lines.append("Matched source line:")
        for line_number, line in matches:
            lines.append(f"{line_number}: {line}")
    elif matches:
        lines.append("Multiple matching source lines found; manual review is required.")
        for line_number, line in matches:
            lines.append(f"{line_number}: {line}")
    else:
        lines.append("No unique source line match found from action name/date context.")

    lines.append("No source edit was applied.")
    return "\n".join(lines)


def format_source_update_preview(action, source_text, fallback_action_id=None):
    return format_source_context_preview(
        action,
        source_text,
        fallback_action_id=fallback_action_id,
        expected_type="source.update.familysearch-id",
        title="Source update preview:",
        wrong_type_message="This action is not a FamilySearch ID source update.",
    )


def format_id_mismatch_preview(action, source_text, fallback_action_id=None):
    return format_source_context_preview(
        action,
        source_text,
        fallback_action_id=fallback_action_id,
        expected_type="review.familysearch-id-mismatch",
        title="FamilySearch ID mismatch preview:",
        wrong_type_message="This action is not a FamilySearch ID mismatch review.",
    )


def find_action(actions, action_id):
    for action in actions:
        if action.get("id") == action_id:
            return action
    return None


def filter_actions(actions, action_type=None):
    if not action_type:
        return actions
    return [action for action in actions if action.get("type") == action_type]


def next_action(actions, action_type=None):
    actions = filter_actions(actions, action_type)
    for action in actions:
        if action.get("requiresApproval"):
            return action
    return actions[0] if actions else None


def format_summary(workup, action_type=None):
    family_search = workup.get("familySearch") or {}
    comparison = workup.get("comparison") or {}
    actions = filter_actions(workup.get("actions") or [], action_type)
    couples = workup.get("couples") or []

    action_counts = {}
    for action in actions:
        action_type = action.get("type") or "unknown"
        action_counts[action_type] = action_counts.get(action_type, 0) + 1

    lines = [
        f"Family: {workup.get('familyId', 'unknown')}",
        f"Source text lines: {workup.get('sourceTextLineCount', 0)}",
        (
            "FamilySearch: "
            + (family_search.get("extractionStatus") or "unknown")
            + f", children {family_search.get('extractedChildCount', 0)}"
        ),
        f"Couples: {len(couples)}",
    ]

    if comparison:
        lines.append(
            "Comparison: "
            + f"rows {comparison.get('rowCount', 0)}, "
            + f"matches {comparison.get('matchCount', 0)}, "
            + f"Juuret-only {comparison.get('juuretOnlyCount', 0)}, "
            + f"HisKi-only {comparison.get('hiskiOnlyCount', 0)}, "
            + f"FamilySearch-only {comparison.get('familySearchOnlyCount', 0)}"
        )
    else:
        lines.append("Comparison: unavailable")

    if action_counts:
        lines.append("Actions:")
        for action_type in sorted(action_counts):
            lines.append(f"- {action_type}: {action_counts[action_type]}")
    else:
        lines.append("Actions: none")

    action = next_action(actions)
    if action:
        lines.append("")
        lines.append("Next:")
        lines.append(action.get("approvalPrompt") or action.get("label") or action.get("type") or action.get("id"))
        if action.get("id"):
            lines.append("ID: " + action["id"])

    return "\n".join(lines)


def load_workup():
    return json.load(sys.stdin)


def main():
    parser = argparse.ArgumentParser(description="Format Juuret Project workup actions.")
    subparsers = parser.add_subparsers(dest="command", required=True)
    summary_parser = subparsers.add_parser("summary")
    summary_parser.add_argument("--type", dest="action_type")
    actions_parser = subparsers.add_parser("actions")
    actions_parser.add_argument("--type", dest="action_type")
    next_parser = subparsers.add_parser("next")
    next_parser.add_argument("--type", dest="action_type")
    action_parser = subparsers.add_parser("action")
    action_parser.add_argument("action_id")
    proposal_parser = subparsers.add_parser("proposal")
    proposal_parser.add_argument("action_id")
    proposal_parser.add_argument("--source-text")
    proposal_parser.add_argument("--source-context", choices=["source-update", "id-mismatch"])

    args = parser.parse_args()
    workup = load_workup()
    actions = workup.get("actions", [])

    if args.command == "summary":
        print(format_summary(workup, action_type=args.action_type))
        return 0

    if args.command == "actions":
        actions = filter_actions(actions, action_type=args.action_type)
        print(json.dumps(actions, indent=2, sort_keys=True))
        return 0

    if args.command == "next":
        action = next_action(actions, action_type=args.action_type)
        if action is None:
            print("No queued actions.")
            return 0
        print(format_action(action))
        return 0

    action = find_action(actions, args.action_id)
    if action is None:
        print(f"Action not found: {args.action_id}", file=sys.stderr)
        return 66

    if args.command == "action":
        print(json.dumps(action, indent=2, sort_keys=True))
    elif args.source_text:
        with open(args.source_text, "r", encoding="utf-8") as source_file:
            source_text = source_file.read()
        if args.source_context == "id-mismatch":
            preview = format_id_mismatch_preview(
                action,
                source_text,
                fallback_action_id=args.action_id,
            )
        else:
            preview = format_source_update_preview(
                action,
                source_text,
                fallback_action_id=args.action_id,
            )
        print(preview)
    else:
        print(format_action(action, fallback_action_id=args.action_id))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
