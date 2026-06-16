# Foundation Models Juuret Prototype

Standalone experiment for parsing a Juuret Kälviällä family block with Apple's
Foundation Models framework.

The runner compiles against the app's real model files:

- `Kalvian Roots/Models/Person.swift`
- `Kalvian Roots/Models/Family.swift`

Foundation Models generates a small DTO marked `@Generable` and `Codable`.
The DTO is then converted into the real `Family`, `Couple`, and `Person`
structs. This keeps the prototype standalone while avoiding a parallel domain
model.

Run:

```sh
./FoundationModelsJuuretPrototype/run.sh
```

Use a family from a roots file:

```sh
./FoundationModelsJuuretPrototype/run.sh \
  --roots-file "$HOME/Documents/JuuretKälviällä.roots" \
  --family-id "KORPI 6"
```

Print the generated schema without calling the model:

```sh
./FoundationModelsJuuretPrototype/run.sh --print-schema
```

Inspect the extracted family text before calling the model:

```sh
./FoundationModelsJuuretPrototype/run.sh \
  --print-input \
  --roots-file "$HOME/Documents/JuuretKälviällä.roots" \
  --family-id "KORPI 6"
```

Requires Xcode beta with the Foundation Models framework and a Mac where
Apple Intelligence / the system language model is available.
