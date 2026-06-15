# FoundationModels Usage Report

Repository: `michaelbendio/Kalvian-Roots`

Scan target: default branch snapshot returned by GitHub code search (`5d6f2a8ef1efd40b5c41524ef6ade030c38f7b94`).

## Summary

Direct uses of `FoundationModels` found:

1. `Kalvian Roots.xcodeproj/project.pbxproj`
2. `Kalvian Roots/Utilities/JuuretError.swift`

No Swift implementation file in the indexed repository currently imports `FoundationModels`.

No direct uses were found for:

- `import FoundationModels`
- `LanguageModelSession`
- `@Generable`
- `Generable`
- FoundationModels `Prompt`
- FoundationModels structured-generation APIs

The current active AI parsing path appears to be the DeepSeek HTTP service in `Kalvian Roots/App/AIServices.swift`, not Apple FoundationModels.

## File: `Kalvian Roots.xcodeproj/project.pbxproj`

### Purpose

This is the Xcode project file. Its FoundationModels-related purpose is to link `FoundationModels.framework` into the app and test targets.

Relevant findings:

- `FoundationModels.framework` appears as a `PBXFileReference`.
- It points to an iPhoneOS 26 SDK path:
  - `Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.0.sdk/System/Library/Frameworks/FoundationModels.framework`
- The framework is added to the app target's Frameworks build phase.
- The framework is also added to the test target's Frameworks build phase.
- The project was created with Xcode tools version 26.0.
- Deployment targets include iOS 26.0 and macOS 26.0.

### Prompt used

None in this file. The project file only links the framework. It does not construct a prompt or call a language model.

### `@Generable` models

None.

### APIs that may have changed since WWDC 2026

Because this file links directly to an SDK-specific framework path under `iPhoneOS26.0.sdk`, it should be rechecked in the current Xcode/SDK:

- Whether `FoundationModels.framework` is still available at that SDK path.
- Whether the framework should be linked explicitly or only imported from Swift source.
- Whether the app target should link the iOS SDK framework while also supporting macOS.
- Whether the framework is supported for the declared platforms in `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"`.

Risk level: **medium**. The reference is SDK-path-sensitive and may be stale if Xcode changed the FoundationModels framework location or platform availability.

## File: `Kalvian Roots/Utilities/JuuretError.swift`

### Purpose

This file defines the app's `JuuretError` enum and localized error messages/recovery suggestions for family extraction, AI service configuration, cross-reference resolution, file management, parsing, and network failures.

Its FoundationModels-related content is legacy error handling:

```swift
case foundationModelsUnavailable  // Keep for legacy compatibility
```

and the corresponding user-facing message:

```swift
return "Foundation Models Framework not available"
```

There is no direct FoundationModels API call in this file.

### Prompt used

None in this file. It only defines errors.

### `@Generable` models

None.

### APIs that may have changed since WWDC 2026

This file does not call FoundationModels APIs, so there are no direct API compatibility risks. The only item to revisit is naming/semantics:

- If the app resumes using FoundationModels, this generic error case may need more specific handling for current availability checks, unsupported devices, model-not-ready states, or session-generation failures.
- The phrase "Foundation Models Framework not available" may no longer match Apple's current terminology or failure modes.

Risk level: **low**.

## Related AI parsing prompt outside direct FoundationModels hits

Although not a direct FoundationModels use, `Kalvian Roots/App/AIServices.swift` contains the active parsing prompt used by `DeepSeekService.parseFamily(familyId:familyText:)`.

### Purpose

`AIServices.swift` defines an `AIService` protocol and implements `DeepSeekService`, which sends a chat-completions request to `https://api.deepseek.com/v1/chat/completions` using model `deepseek-chat`.

### Prompt used

The user prompt begins:

```text
Parse the following family record and return ONLY a valid JSON object.

CRITICAL: Return ONLY the JSON object - no markdown, no explanation, no ```json tags.

JSON SCHEMA TO USE:
{
  "familyId": "string",
  "pageReferences": ["array of page numbers as strings"],
  "couples": [
    {
      "husband": {
        "name": "string (given name only)",
        "patronymic": "string or null",
        "birthDate": "string or null",
        "deathDate": "string or null (keep 'isoviha' as-is)",
        "asChild": "string or null (from {family ref})",
        "familySearchId": "string or null (from <ID>)",
        "noteMarkers": ["array of asterisks: *, **, *** (NO parentheses)"]
      },
      "wife": {
        "name": "string",
        "patronymic": "string or null",
        "birthDate": "string or null",
        "deathDate": "string or null",
        "asChild": "string or null",
        "familySearchId": "string or null",
        "noteMarkers": ["array of asterisks: *, **, ***"]
      },
      "marriageDate": "string or null (2-digit year, MAY include 'n' prefix)",
      "fullMarriageDate": "string or null (dd.mm.yyyy, MAY include 'n' prefix)",
      "children": [
        {
          "name": "string",
          "birthDate": "string or null",
          "deathDate": "string or null",
          "marriageDate": "string or null",
          "spouse": "string or null",
          "asParent": "string or null",
          "familySearchId": "string or null",
          "noteMarkers": ["array of asterisks: *, **, ***"]
        }
      ],
      "childrenDiedInfancy": null,
      "coupleNotes": []
    }
  ],
  "notes": ["array of family notes"],
  "noteDefinitions": {"*": "note text", "**": "another note"}
}
```

The prompt then gives extraction rules for:

- parsing only the requested family ID,
- creating separate couple entries for each marriage,
- preserving dates exactly,
- ignoring `synt.` origin-place phrases,
- creating placeholder husband/wife objects when spouse data is missing,
- stripping numeric marriage prefixes from spouse names,
- extracting note markers and note definitions,
- preserving approximate-date prefixes such as `n 1730`,
- assigning children to the correct couple.

The system prompt sent to DeepSeek is:

```text
You are a Finnish genealogy data extraction expert. Return ONLY valid JSON with no additional text.
```

### `@Generable` models

None. This path uses manual JSON prompting and `JSONSerialization`, not FoundationModels structured generation.

### APIs that may have changed since WWDC 2026

If this DeepSeek prompt is migrated to FoundationModels, these FoundationModels areas should be checked against the current SDK:

- `LanguageModelSession` construction and availability checks.
- `respond(to:)` / structured response API spelling and signatures.
- `@Generable` macro syntax and restrictions.
- `@Guide` or field-guidance syntax, if used to replace parts of the prompt.
- Error types thrown by session creation or generation calls.
- Streaming vs non-streaming generation APIs.
- Tool-calling APIs, if FamilySearch or HisKi lookup is exposed as model tools.
- Guardrail/safety failure reporting and recoverability.

Risk level if migrated: **high**, because the current prompt relies on detailed free-form extraction rules and manual JSON schema text. A FoundationModels migration would likely require explicit `@Generable` structs plus guidance annotations rather than simply reusing the existing prompt unchanged.

## Recommended follow-up before implementing a branch

1. Remove or repair the explicit SDK path reference if Xcode 26+ now resolves FoundationModels differently.
2. Decide whether FoundationModels should replace or supplement `DeepSeekService` behind the existing `AIService` protocol.
3. Define `@Generable` structs corresponding to the current JSON schema before attempting prompt migration.
4. Keep DeepSeek as a fallback until FoundationModels extraction quality is validated on difficult families: multiple spouses, `synt.` origin phrases, note markers, approximate dates, and child-to-couple assignment.
5. Add a small compatibility test target that compiles a minimal `LanguageModelSession` and a minimal `@Generable` response model under the installed Xcode SDK.
