## Union types for oneOf/anyOf — design notes

This document captures design decisions and trade-offs around union type support for OpenAPI `oneOf` / `anyOf` in `dart_swagger_to_models`.

### 1. Current behavior (as of v0.5.x)

- For `oneOf` / `anyOf` **without** a discriminator:
  - The generator creates a **single wrapper class** with a `dynamic` payload:
    - Example: `class Value { final dynamic value; ... }`.
  - This provides a safe container, but the caller is responsible for runtime checks and casting.

- For `oneOf` / `anyOf` **with discriminator and per-variant enums** (v0.6.1 prototype):
  - The generator creates a **union-style class** with:
    - A non-nullable discriminator field (e.g. `final String type;`).
    - One nullable field per variant (e.g. `final Cat? cat; final Dog? dog;`).
    - Named constructors `fromCat`, `fromDog`, ….
    - `fromJson` that dispatches based on the discriminator.
    - `toJson` that delegates to the active variant.
    - `when` / `maybeWhen` helpers for pattern-matching style usage.
  - This works for the common OpenAPI pattern:
    - Discriminator property (e.g. `type`).
    - Each variant schema has that property as an enum with a single literal (`'cat'`, `'dog'`, …).

### 2. Pros and cons of the current union implementation

**Pros:**

- **Type-safe entry points**:
  - `Pet.fromJson` creates a concrete `Cat` / `Dog` instance and wraps it in a strongly typed union.
  - `when` / `maybeWhen` expose variant-specific types (`Cat`, `Dog`, …) without casts.
- **Minimal disruption to existing architecture**:
  - The union is implemented as a regular class, independent of global style (`plain_dart` / `json_serializable` / `freezed`).
  - No changes required in generator strategies for basic behavior.
- **Backwards compatibility**:
  - Schemas without discriminator (or with unsupported patterns) still fall back to the existing dynamic wrapper.

**Cons:**

- **Many nullable fields for large unions**:
  - For a schema with many variants (`Pet` with 10–20 types), the generated class will have many `T?` fields.
  - At runtime only one of them is actually used.
  - This is acceptable in practice for typical API models, but not “ideal” from a pure type theory standpoint.
- **Manual usage without helpers is verbose**:
  - If the consumer does not use `when` / `maybeWhen`, they might end up writing `if (pet.cat != null) { ... }` checks manually.
- **Not using Dart 3 `sealed` hierarchy yet**:
  - We rely on a single class with nullable fields instead of multiple sealed subclasses.
  - This means no exhaustive `switch` over union variants at the language level.

### 3. Why not sealed classes right away?

Dart 3 provides `sealed` / `base` / `final` classes, which could be used to model union types more idiomatically:

```dart
sealed class Pet {
  const Pet();
}

final class PetCat extends Pet {
  final Cat value;
  const PetCat(this.value);
}

final class PetDog extends Pet {
  final Dog value;
  const PetDog(this.value);
}
```

This approach would give:

- **No nullable payload fields** — each instance stores exactly one variant.
- **Exhaustive pattern matching** via `switch` expressions/statements.
- Clean separation of variant-specific logic into dedicated classes.

However, there are practical challenges for `dart_swagger_to_models`:

- **Multiple classes per schema**:
  - One OpenAPI schema would expand into a sealed base + N subclasses.
  - This complicates file layout and marker-based regeneration (per-file mode, custom code regions, etc.).
- **Interaction with styles**:
  - `plain_dart` can work with sealed classes directly.
  - `json_serializable` and `freezed` already have their own approaches to unions, and we must avoid conflicting patterns.
- **API design stability**:
  - Introducing sealed unions changes public API shape significantly.
  - We should design this behind a feature flag and stabilize the API before turning it on by default.

### 4. Proposed future direction

The current union implementation is a **pragmatic first step**. For future versions (v0.6+), we should:

1. **Introduce configuration for union implementation**:
   - Example:
     - `unionImplementation: 'single_class' | 'sealed' | 'freezed'`.
     - Or separate flags like `useSealedUnionsForOneOf: true/false`.
   - Defaults should remain backwards compatible (`single_class`).

2. **Design sealed union generation for `plain_dart`**:
   - Generate a sealed base class + final subclasses.
   - Provide `fromJson` / `toJson` helpers on the base class.
   - Ensure compatibility with per-file mode and marker-based regeneration.

3. **Explore deeper integration with `freezed`**:
   - For the `freezed` style, consider generating proper `@freezed` unions for `oneOf` / `anyOf`.
   - Map discriminator tokens to union cases in a predictable way.

4. **Document trade-offs clearly**:
   - Explain when to choose which union implementation.
   - Provide migration guidance for users who want to move from `single_class` to `sealed` or `freezed` unions.

### 5. Summary

- **Now**:
  - We have a working, type-safe union wrapper for `oneOf` / `anyOf` with discriminators using a single class and nullable variant fields.
  - Non-discriminator schemas still use the original dynamic wrapper.
- **Later**:
  - We plan to introduce configurable union implementations (including sealed and `freezed`-based unions) once the API and code generation patterns are fully designed and tested.

