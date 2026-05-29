#!/usr/bin/env python3
import argparse
import json
import re
import sys
from datetime import datetime

ACTION_KIND_TYPES = {
    "source-update": "source.update.familysearch-id",
    "id-mismatch": "review.familysearch-id-mismatch",
}


def action_type_for(kind=None, action_type=None):
    if action_type:
        return action_type
    if not kind:
        return None
    return ACTION_KIND_TYPES[kind]


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


def proposed_source_edit(action, source_line):
    context = action.get("context") or {}
    juuret = context.get("juuret") or {}
    family_search = context.get("familySearch") or {}
    new_id = action.get("personId") or family_search.get("familySearchId")
    old_id = juuret.get("familySearchId")
    person_name = juuret.get("name") or action.get("personName")
    action_type = action.get("type")

    if not new_id:
        return None, "No FamilySearch ID is available for the proposed edit."

    if action_type == "source.update.familysearch-id":
        if re.search(r"<[A-Z0-9]{4}-[A-Z0-9]{3,}>", source_line):
            return None, "Matched source line already contains a FamilySearch ID."
        if not person_name or person_name not in source_line:
            return None, "Matched source line does not contain the Juuret person name exactly."
        return source_line.replace(person_name, f"{person_name} <{new_id}>", 1), None

    if action_type == "review.familysearch-id-mismatch":
        if not old_id:
            return None, "Juuret does not provide the old FamilySearch ID needed for replacement."
        old_token = f"<{old_id}>"
        if old_token not in source_line:
            return None, f"Matched source line does not contain {old_token}."
        return source_line.replace(old_token, f"<{new_id}>", 1), None

    return None, "This action type does not support a source edit dry run."


def format_source_edit_dry_run(action, source_text, fallback_action_id=None):
    lines, edit = source_edit_preview_lines(
        action,
        source_text,
        fallback_action_id=fallback_action_id,
        title="Source edit dry run:",
        final_line="No source edit was applied.",
    )
    return "\n".join(lines)


def source_edit_preview_lines(
    action,
    source_text,
    fallback_action_id=None,
    title="Source edit dry run:",
    final_line="No source edit was applied.",
):
    lines = [format_action(action, fallback_action_id=fallback_action_id)]
    lines.append("")
    lines.append(title)

    if action.get("type") not in {
        "source.update.familysearch-id",
        "review.familysearch-id-mismatch",
    }:
        lines.append("This action type does not support a source edit dry run.")
        lines.append(final_line)
        return lines, None

    matches = matching_source_lines(source_text, action)
    if len(matches) != 1:
        if matches:
            lines.append("Multiple matching source lines found; manual review is required.")
            for line_number, line in matches:
                lines.append(f"{line_number}: {line}")
        else:
            lines.append("No unique source line match found from action name/date context.")
        lines.append(final_line)
        return lines, None

    line_number, old_line = matches[0]
    new_line, reason = proposed_source_edit(action, old_line)
    if reason:
        lines.append(reason)
        lines.append(final_line)
        return lines, None

    lines.extend(
        [
            f"Line: {line_number}",
            "Old:",
            old_line,
            "New:",
            new_line,
            final_line,
        ]
    )
    return lines, {
        "line_number": line_number,
        "old_line": old_line,
        "new_line": new_line,
    }


def apply_source_edit(action, source_text, fallback_action_id=None):
    lines, edit = source_edit_preview_lines(
        action,
        source_text,
        fallback_action_id=fallback_action_id,
        title="Source edit apply:",
        final_line="No source edit was applied.",
    )

    if edit is None:
        return source_text, "\n".join(lines), False

    old_line = edit["old_line"]
    new_line = edit["new_line"]
    if source_text.count(old_line) != 1:
        lines.append("The matched source line is not unique in the full source file.")
        lines.append("No source edit was applied.")
        return source_text, "\n".join(lines), False

    lines[-1] = "Source edit applied."
    return source_text.replace(old_line, new_line, 1), "\n".join(lines), True


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
    summary_parser.add_argument("--kind", choices=sorted(ACTION_KIND_TYPES))
    actions_parser = subparsers.add_parser("actions")
    actions_parser.add_argument("--type", dest="action_type")
    actions_parser.add_argument("--kind", choices=sorted(ACTION_KIND_TYPES))
    next_parser = subparsers.add_parser("next")
    next_parser.add_argument("--type", dest="action_type")
    next_parser.add_argument("--kind", choices=sorted(ACTION_KIND_TYPES))
    action_parser = subparsers.add_parser("action")
    action_parser.add_argument("action_id")
    proposal_parser = subparsers.add_parser("proposal")
    proposal_parser.add_argument("action_id")
    proposal_parser.add_argument("--source-text")
    proposal_parser.add_argument("--source-context", choices=["source-update", "id-mismatch"])
    proposal_parser.add_argument("--source-edit-dry-run", action="store_true")
    proposal_parser.add_argument("--source-edit-apply", action="store_true")

    args = parser.parse_args()
    workup = load_workup()
    actions = workup.get("actions", [])
    requested_action_type = action_type_for(
        kind=getattr(args, "kind", None),
        action_type=getattr(args, "action_type", None),
    )

    if args.command == "summary":
        print(format_summary(workup, action_type=requested_action_type))
        return 0

    if args.command == "actions":
        actions = filter_actions(actions, action_type=requested_action_type)
        print(json.dumps(actions, indent=2, sort_keys=True))
        return 0

    if args.command == "next":
        action = next_action(actions, action_type=requested_action_type)
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
        if args.source_edit_apply:
            updated_text, preview, applied = apply_source_edit(
                action,
                source_text,
                fallback_action_id=args.action_id,
            )
            if applied:
                with open(args.source_text, "w", encoding="utf-8") as source_file:
                    source_file.write(updated_text)
        elif args.source_edit_dry_run:
            preview = format_source_edit_dry_run(
                action,
                source_text,
                fallback_action_id=args.action_id,
            )
        elif args.source_context == "id-mismatch":
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
