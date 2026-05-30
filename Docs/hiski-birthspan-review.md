HisKi Birth-Span Review
=======================

Purpose
-------

Kalvian Roots uses HisKi birth-span searches to find possible children of a
couple. These searches are useful evidence-gathering tools, but the result set
must not be treated as the children of one family by default.

This note records the review discipline for working with those results.


Core Rule
---------

A HisKi birth-span result is a candidate pool.

It is not, by itself, a family reconstruction.

The query is based on:

    father given name + father patronymic
    mother given name + mother patronymic
    parish
    broad birth-year span

In eighteenth- and nineteenth-century Central Ostrobothnia, given-name pools are
small enough that multiple couples in the same parish can share the same given
and patronymic names during overlapping childbearing years.


Review Practice
---------------

Always open the Lapset link and inspect the full HisKi birth-span result before
adding children to FamilySearch or treating HisKi-only rows as belonging to the
target couple.

During review, check:

    - whether the rows form one chronological family or several clusters
    - whether farm or village names change in a way that suggests separate
      families
    - whether birth spacing is biologically plausible
    - whether the total childbearing span is plausible for one mother
    - whether Juuret Kälviällä independently places the child in the family
    - whether FamilySearch already has a matching child under different parents

Farm and village names are only hints. They are often missing, and families can
move. But when present, they can reveal likely clusters that should not be
collapsed automatically.


Actionability
-------------

Rows supported only by the parent-name birth-span query should be treated as
review candidates.

Do not treat a HisKi-only row as an actionable missing FamilySearch child unless
there is stronger corroboration, such as:

    - the child is present in Juuret Kälviällä for the same family
    - the child already matches a FamilySearch child by name and birth date
    - additional source context ties the row to the target couple

HisKi-only candidates may still be correct. The point is that the birth-span
query alone does not prove membership in the family.


FamilySearch Duplicate Risk
---------------------------

Adding a HisKi candidate child to FamilySearch can create duplicate family
structures when the child already exists under another same-named parent couple.

Before adding a HisKi-only child, future tooling should check whether a matching
FamilySearch person already exists under different parents. If so, the workflow
should shift from "add missing child" to "review possible existing child or
parent duplicate."

The FamilySearch merge itself must remain an explicit human action in the
FamilySearch UI.


Future Tooling
--------------

A more advanced Kalvian Roots workflow should support collaborative review of
HisKi candidate pools.

Useful tools include:

    - cluster HisKi birth-span rows by farm, village, and chronology
    - compare each cluster with Juuret children
    - flag HisKi-only rows as review candidates rather than missing children
    - detect matching FamilySearch children under different parent IDs
    - compare possible duplicate fathers and mothers side by side
    - open the appropriate FamilySearch merge comparison screens
    - record review decisions such as likely same family, likely different
      family, unresolved, or merge completed

Kalvian Roots should present source claims with provenance. A HisKi query match,
a Juuret family entry, and a FamilySearch parent-child relationship are different
kinds of evidence and should remain distinguishable during review.
