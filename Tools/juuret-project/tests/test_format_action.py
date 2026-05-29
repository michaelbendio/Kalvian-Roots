import pathlib
import sys
import unittest


TOOL_DIR = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOL_DIR))

import format_action


class FormatActionTests(unittest.TestCase):
    def test_formats_source_update_proposal_with_context(self):
        action = {
            "id": "TEST 2:source.update.familysearch-id:0:elis:1760-06-12:AB12-CD:Liisa",
            "type": "source.update.familysearch-id",
            "personName": "Liisa",
            "personId": "AB12-CD",
            "requiresApproval": True,
            "approvalPrompt": "Should I add AB12-CD to Liisa in the canonical Juuret source text?",
            "context": {
                "coupleIndex": 0,
                "birthDate": "1760-06-12",
                "status": "Missing in HisKi",
                "juuret": {
                    "name": "Liisa",
                    "birthDate": "1760-06-12",
                },
                "familySearch": {
                    "name": "Liisa Mattsdotter",
                    "birthDate": "1760-06-12",
                    "familySearchId": "AB12-CD",
                },
            },
        }

        self.assertEqual(
            format_action.format_action(action),
            "\n".join(
                [
                    "Should I add AB12-CD to Liisa in the canonical Juuret source text?",
                    "",
                    "Action: source.update.familysearch-id",
                    "ID: TEST 2:source.update.familysearch-id:0:elis:1760-06-12:AB12-CD:Liisa",
                    "Person: Liisa (AB12-CD)",
                    "Couple: 1",
                    "Status: Missing in HisKi",
                    "Birth: 1760-06-12",
                    "",
                    "Juuret: Liisa, 1760-06-12",
                    "FamilySearch: Liisa Mattsdotter, 1760-06-12, AB12-CD",
                    "",
                    "Requires explicit approval before changing source data.",
                ]
            ),
        )

    def test_next_action_prefers_approval_required_actions(self):
        actions = [
            {"id": "extract", "requiresApproval": False},
            {"id": "approve", "requiresApproval": True},
        ]

        self.assertEqual(format_action.next_action(actions), actions[1])

    def test_next_action_can_filter_by_type(self):
        actions = [
            {
                "id": "review",
                "type": "review.comparison",
                "requiresApproval": True,
            },
            {
                "id": "source-update",
                "type": "source.update.familysearch-id",
                "requiresApproval": True,
            },
        ]

        self.assertEqual(
            format_action.next_action(
                actions,
                action_type="source.update.familysearch-id",
            ),
            actions[1],
        )

    def test_formats_workup_summary_with_next_action(self):
        workup = {
            "familyId": "SAKERI 1",
            "sourceTextLineCount": 14,
            "familySearch": {
                "extractionStatus": "available",
                "extractedChildCount": 12,
            },
            "couples": [{}, {}],
            "comparison": {
                "rowCount": 12,
                "matchCount": 9,
                "juuretOnlyCount": 1,
                "hiskiOnlyCount": 0,
                "familySearchOnlyCount": 2,
            },
            "actions": [
                {
                    "id": "SAKERI 1:familysearch.add-child:gusta",
                    "type": "familysearch.add-child",
                    "requiresApproval": True,
                    "label": "Review whether this child should be added.",
                },
                {
                    "id": "SAKERI 1:review.comparison:malin",
                    "type": "review.comparison",
                    "requiresApproval": True,
                },
            ],
        }

        self.assertEqual(
            format_action.format_summary(workup),
            "\n".join(
                [
                    "Family: SAKERI 1",
                    "Source text lines: 14",
                    "FamilySearch: available, children 12",
                    "Couples: 2",
                    "Comparison: rows 12, matches 9, Juuret-only 1, HisKi-only 0, FamilySearch-only 2",
                    "Actions:",
                    "- familysearch.add-child: 1",
                    "- review.comparison: 1",
                    "",
                    "Next:",
                    "Review whether this child should be added.",
                    "ID: SAKERI 1:familysearch.add-child:gusta",
                ]
            ),
        )

    def test_summary_can_filter_action_counts_by_type(self):
        workup = {
            "familyId": "SAKERI 1",
            "sourceTextLineCount": 14,
            "familySearch": {
                "extractionStatus": "available",
                "extractedChildCount": 12,
            },
            "couples": [{}],
            "comparison": None,
            "actions": [
                {
                    "id": "review",
                    "type": "review.comparison",
                    "requiresApproval": True,
                },
                {
                    "id": "source-update",
                    "type": "source.update.familysearch-id",
                    "requiresApproval": True,
                    "approvalPrompt": "Should I add AB12-CD to Liisa?",
                },
            ],
        }

        self.assertEqual(
            format_action.format_summary(
                workup,
                action_type="source.update.familysearch-id",
            ),
            "\n".join(
                [
                    "Family: SAKERI 1",
                    "Source text lines: 14",
                    "FamilySearch: available, children 12",
                    "Couples: 1",
                    "Comparison: unavailable",
                    "Actions:",
                    "- source.update.familysearch-id: 1",
                    "",
                    "Next:",
                    "Should I add AB12-CD to Liisa?",
                    "ID: source-update",
                ]
            ),
        )

    def test_source_update_preview_shows_matching_source_lines_without_editing(self):
        action = {
            "id": "source-update",
            "type": "source.update.familysearch-id",
            "personName": "Liisa",
            "personId": "AB12-CD",
            "requiresApproval": True,
            "approvalPrompt": "Should I add AB12-CD to Liisa?",
            "context": {
                "birthDate": "1760-06-12",
                "juuret": {
                    "name": "Liisa",
                    "birthDate": "1760-06-12",
                },
            },
        }
        source_text = "\n".join(
            [
                "TEST 2",
                "Lapset",
                "Liisa 12.06.1760",
            ]
        )

        self.assertEqual(
            format_action.format_source_update_preview(action, source_text),
            "\n".join(
                [
                    "Should I add AB12-CD to Liisa?",
                    "",
                    "Action: source.update.familysearch-id",
                    "ID: source-update",
                    "Person: Liisa (AB12-CD)",
                    "Birth: 1760-06-12",
                    "",
                    "Juuret: Liisa, 1760-06-12",
                    "",
                    "Requires explicit approval before changing source data.",
                    "",
                    "Source update preview:",
                    "Matched source line:",
                    "3: Liisa 12.06.1760",
                    "No source edit was applied.",
                ]
            ),
        )

    def test_source_update_preview_flags_multiple_matching_source_lines(self):
        action = {
            "id": "source-update",
            "type": "source.update.familysearch-id",
            "personName": "Liisa",
            "personId": "AB12-CD",
            "requiresApproval": True,
            "approvalPrompt": "Should I add AB12-CD to Liisa?",
            "context": {
                "birthDate": "1760-06-12",
                "juuret": {
                    "name": "Liisa",
                    "birthDate": "1760-06-12",
                },
            },
        }
        source_text = "\n".join(
            [
                "TEST 2",
                "Liisa 12.06.1760",
                "Liisa 12.06.1760 duplicate",
            ]
        )

        preview = format_action.format_source_update_preview(action, source_text)

        self.assertIn("Multiple matching source lines found; manual review is required.", preview)
        self.assertIn("2: Liisa 12.06.1760", preview)
        self.assertIn("3: Liisa 12.06.1760 duplicate", preview)


if __name__ == "__main__":
    unittest.main()
