# Git Commit Skill

## Goal

Generate clear and professional Conventional Commit messages.

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

## Rules

Subject:

* imperative mood
* lowercase
* concise
* maximum 72 characters

Body:

Explain:

* Why
* What changed
* Impact

Avoid describing implementation details unless necessary.

---

## Format

<type>(<scope>): <summary>

Why

* ...

What Changed

* ...

Impact

* ...

---

## Examples

feat(contract): support manual payment fallback

fix(invoice): prevent duplicate invoice generation

refactor(customer): simplify validation flow

test(contract): add mandate failure integration tests

---

## Before Generating

Analyze:

* Git diff
* Changed files
* Business purpose

Infer the most appropriate commit type and scope.

If multiple unrelated changes exist, recommend splitting them into multiple commits instead of generating one commit.

---

## Co-Authored-By

Do NOT add `Co-Authored-By` line. Commit message body only contains
Why / What Changed / Impact.
