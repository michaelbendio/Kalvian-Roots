#!/usr/bin/env python3
import argparse
import json
import sys


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


def find_action(actions, action_id):
    for action in actions:
        if action.get("id") == action_id:
            return action
    return None


def next_action(actions):
    for action in actions:
        if action.get("requiresApproval"):
            return action
    return actions[0] if actions else None


def load_actions():
    return json.load(sys.stdin).get("actions", [])


def main():
    parser = argparse.ArgumentParser(description="Format Juuret Project workup actions.")
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("actions")
    subparsers.add_parser("next")
    action_parser = subparsers.add_parser("action")
    action_parser.add_argument("action_id")
    proposal_parser = subparsers.add_parser("proposal")
    proposal_parser.add_argument("action_id")

    args = parser.parse_args()
    actions = load_actions()

    if args.command == "actions":
        print(json.dumps(actions, indent=2, sort_keys=True))
        return 0

    if args.command == "next":
        action = next_action(actions)
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
    else:
        print(format_action(action, fallback_action_id=args.action_id))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
