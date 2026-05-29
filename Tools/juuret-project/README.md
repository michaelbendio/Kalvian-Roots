# Juuret Project CLI

This is the first conversation-oriented tool surface for Kalvian Roots workups.
It reads the app's `/workup.json` output and formats it for chat-driven review.

The Kalvian Roots macOS app must be running unless `--workup-json` is used.

## Commands

Fetch the full workup JSON:

```sh
Tools/juuret-project/juuret-project workup "SAKERI 1"
```

Fetch the canonical family source text as plain text:

```sh
Tools/juuret-project/juuret-project source "SAKERI 1"
```

Show a compact checkpoint:

```sh
Tools/juuret-project/juuret-project summary "SAKERI 1"
```

List queued actions as JSON:

```sh
Tools/juuret-project/juuret-project actions "SAKERI 1"
```

Show the next approval-oriented proposal:

```sh
Tools/juuret-project/juuret-project next "SAKERI 1"
```

Show one action as JSON:

```sh
Tools/juuret-project/juuret-project action "SAKERI 1" "ACTION_ID"
```

Show one action as proposal text:

```sh
Tools/juuret-project/juuret-project proposal "SAKERI 1" "ACTION_ID"
```

Preview the source line context for a FamilySearch ID source update without
editing the canonical file:

```sh
Tools/juuret-project/juuret-project source-update-preview "SAKERI 1" "ACTION_ID"
```

Preview the source line context for a FamilySearch ID mismatch review:

```sh
Tools/juuret-project/juuret-project id-mismatch-preview "SAKERI 1" "ACTION_ID"
```

Show a proposed old/new source line without editing the canonical file:

```sh
Tools/juuret-project/juuret-project source-edit-dry-run "SAKERI 1" "ACTION_ID"
```

Apply an approved source edit to the canonical roots file:

```sh
Tools/juuret-project/juuret-project source-edit-apply "SAKERI 1" "ACTION_ID"
```

Use a non-default roots file for an apply:

```sh
Tools/juuret-project/juuret-project source-edit-apply "SAKERI 1" "ACTION_ID" \
  --roots-file /path/to/JuuretKälviällä.roots
```

Focus on FamilySearch ID source updates:

```sh
Tools/juuret-project/juuret-project next "SAKERI 1" --kind source-update
```

Focus on FamilySearch ID mismatches:

```sh
Tools/juuret-project/juuret-project next "SAKERI 1" --kind id-mismatch
```

Use a saved workup JSON file:

```sh
Tools/juuret-project/juuret-project summary "SAKERI 1" --workup-json /path/to/workup.json
```

Preview a source update fully offline:

```sh
Tools/juuret-project/juuret-project source-update-preview "SAKERI 1" "ACTION_ID" \
  --workup-json /path/to/workup.json \
  --source-text /path/to/source.txt
```

## Approval Boundary

Commands that show proposals or dry-runs do not edit the canonical Juuret
source text. `source-edit-apply` is the explicit write command and should only
be run after the proposed old/new source line has been reviewed and approved.
