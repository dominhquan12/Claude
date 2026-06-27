# Git Commit Skill

## Goal

Generate clear, professional Conventional Commit messages that accurately describe the purpose of a change.

Prefer concise commit messages. Only include a detailed body when it adds meaningful context.

---

## Commit Types

Use one of:

* feat
* fix
* refactor
* test
* docs
* style
* perf
* build
* ci
* chore
* revert

---

## Subject

Format:

```text
<type>(<scope>): <summary>
```

Rules:

* imperative mood
* lowercase
* concise
* maximum 72 characters

Examples:

```text
feat(contract): support manual payment fallback
fix(invoice): prevent duplicate invoice generation
refactor(customer): simplify validation flow
```

---

## Commit Body

### Small changes

For simple changes (style, docs, tests, formatting, minor refactoring, typo fixes, dependency updates, etc.), use only the subject unless additional context is genuinely helpful.

Example:

```text
style(contract): remove unused imports
```

---

### Business or Functional changes

For features, bug fixes, significant refactoring, or any change affecting business behavior, include a body using the following sections:

```text
Why

- Why the change was needed.

What

- High-level summary of what changed.

Impact

- Business, user, or technical impact.
```

Guidelines:

* Explain **why** more than **how**.
* Focus on intent, not implementation details.
* Keep each section concise.

Example:

```text
feat(offer): support dual electricity and solar products

Why

- Dutch households may have both electricity consumption and solar production under one EAN.

What

- Allow offers to contain separate electricity and solar products.
- Update validation and usage aggregation.

Impact

- Support real-world energy scenarios while remaining backward compatible.
```

---

## Before Generating

Always:

1. Review the Git diff.
2. Review the changed files.
3. Infer the business purpose.
4. Choose the most appropriate commit type and scope.

If multiple unrelated changes exist, recommend splitting them into multiple commits instead of generating a single commit.

---

## Restrictions

* Do not invent changes that are not present in the Git diff.
* Do not include implementation details unless necessary.
* Do not include `Co-Authored-By`.
* Do not mention AI assistance.
* Prefer one focused commit per logical change.
