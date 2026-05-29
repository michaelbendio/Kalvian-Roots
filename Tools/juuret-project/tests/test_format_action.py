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


if __name__ == "__main__":
    unittest.main()
