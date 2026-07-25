import unittest

from search_spouse import (
    extract_spouse_given_name,
    find_matches,
    names_match_pair,
)


ROOTS_TEXT = """canonical

HERLEVI 7, page 63
★ 18.03.1738    Lauri Juhonp. <M88Q-6QM>
★ 06.12.1739    Anna Iisakint. <M8ZY-W6L>
∞ 21.10.1759.
Lapset
★ 20.10.1762    Antti <L4ML-1PX>        ∞ 95 Maria Kinnari <LV7S-8L2> Herlevi 9
★ 10.06.1781    Anna Stina <KLQ7-7QK>   ∞ 06 Antti Norppa <K2FV-VG5>

HERLEVI 9, page 64
★ 20.10.1762    Antti Laurinpoika <L4ML-1PX>
★ 09.03.1770    Maria Abramintytär <LV7S-8L2>
∞ 06.12.1795.
Lapset
★ 08.04.1812    Jaakko <GSVF-L74>       ∞ 22.10.1837 leski Fredrika Korpi

TEST 1, page 99
★ 1800          Märta Matint. <AAAA-BBB>
★ 1798          Juhö Juhonp. <CCCC-DDD>
Lapset
"""


class SpouseSearchTests(unittest.TestCase):
    def test_finds_parent_couple_in_either_name_order(self) -> None:
        matches = find_matches(ROOTS_TEXT, "Maria", "Antti")

        self.assertEqual(
            [(match.family_id, match.relationship) for match in matches],
            [
                ("HERLEVI 7", "Married child"),
                ("HERLEVI 9", "Parents"),
            ],
        )

    def test_finds_married_child_when_marriage_date_and_qualifier_are_present(
        self,
    ) -> None:
        matches = find_matches(ROOTS_TEXT, "Fredrika", "Jaakko")

        self.assertEqual(len(matches), 1)
        self.assertEqual(matches[0].family_id, "HERLEVI 9")
        self.assertEqual(matches[0].relationship, "Married child")

    def test_uses_only_first_given_name_for_people_with_multiple_given_names(
        self,
    ) -> None:
        matches = find_matches(ROOTS_TEXT, "Anna", "Antti")

        self.assertEqual(len(matches), 1)
        self.assertIn("Anna Stina", matches[0].couple_lines[0])

    def test_matching_is_case_and_diacritic_insensitive(self) -> None:
        self.assertTrue(names_match_pair("Märta", "Juhö", "juho", "marta"))
        matches = find_matches(ROOTS_TEXT, "juho", "marta")
        self.assertEqual(len(matches), 1)
        self.assertEqual(matches[0].relationship, "Parents")

    def test_spouse_name_parser_skips_reference_year_and_qualifiers(self) -> None:
        self.assertEqual(
            extract_spouse_given_name(
                "★ 1698 Maria ∞ 23 sot. Simo Bohm <M8ZY-SC2>"
            ),
            "Simo",
        )
        self.assertEqual(
            extract_spouse_given_name(
                "★ 1812 Jaakko ∞ 22.10.1837 leski Fredrika Korpi"
            ),
            "Fredrika",
        )

    def test_does_not_match_unmarried_children(self) -> None:
        matches = find_matches(ROOTS_TEXT, "Lauri", "Jaakko")
        self.assertEqual(matches, [])


if __name__ == "__main__":
    unittest.main()
