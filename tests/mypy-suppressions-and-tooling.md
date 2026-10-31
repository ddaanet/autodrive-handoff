# mypy guidelines, part 2: suppression debt through gotchas

Strict mode, config hygiene and annotation practices are in
[mypy-guidelines.md](mypy-guidelines.md).

## Avoiding suppression debt

- **DO write `# type: ignore[code]` with the specific error code, never a
  bare `# type: ignore`.** The coded form "only ignore[s] specific errors
  on the line," which "prevents accidentally silencing unexpected errors
  and documents the purpose"
  ([common_issues.html](https://mypy.readthedocs.io/en/stable/common_issues.html)).
  Bare ignores mask future, unrelated errors on that line.
- **DO let `warn_unused_ignores` (in `--strict`) garbage-collect stale
  ignores.** It "report[s] an error whenever your code uses a
  `# type: ignore` comment on a line that is not actually generating an
  error"
  ([command_line.html](https://mypy.readthedocs.io/en/stable/command_line.html)),
  so suppressions can't outlive the bug they hid. (Enforce
  `ignore-without-code` if you want bare ignores to be a hard error.)
- **PREFER `assert` for narrowing over an ignore.** An ignore hides the
  signal; an `assert` proves the invariant and narrows the type
  ([common_issues.html](https://mypy.readthedocs.io/en/stable/common_issues.html)).

## mypy + ruff: division of labor

Astral's own guidance: "use Ruff in conjunction with a type checker, like
Mypy [...] with Ruff providing faster feedback on lint violations and the
type checker providing more detailed feedback on type errors"
([ruff FAQ](https://docs.astral.sh/ruff/faq/)).

- **Ruff owns annotation *presence*** via the `ANN` group
  (flake8-annotations), which lints for missing annotations on function
  defs/args/returns. With `select = ["ALL"]` you get `ANN` for
  free. This **overlaps the intent of** `disallow_untyped_defs` in
  `--strict`: both want the annotation present. The overlap is benign,
  but the tools are not identical — ruff lints *presence* (a missing
  annotation), mypy checks *correctness* (the annotation is sound). A
  missing-annotation finding may surface from either; a wrong-annotation
  finding only from mypy. (The ruff FAQ recommends pairing the two but
  does not equate `ANN` with `disallow_untyped_defs`
  — [ruff FAQ](https://docs.astral.sh/ruff/faq/).)
- **Ruff owns import placement** via `TC`/`TCH` (flake8-type-checking):
  `TC001`/`TC002`/`TC003` flag first-party/third-party/stdlib imports used
  only in annotations, suggesting an `if TYPE_CHECKING:` block to cut
  runtime overhead
  ([TC001](https://docs.astral.sh/ruff/rules/typing-only-first-party-import/)).
  Deliberately ignoring `TC001`–`TC003` is a defensible choice for small
  scripts where the runtime-import cost is negligible and `TYPE_CHECKING`
  blocks add noise; for a large or import-heavy codebase, leave them on.
  Either way, make the call explicit in config rather than by accident.
- **mypy owns type *correctness*** — narrowing, return-type soundness,
  generics, overload resolution. Ruff does not type-check. Keep
  type-semantics rules in mypy and lint-shape rules in ruff; don't try to
  reproduce mypy checks with ruff or vice versa.

## mypy vs ty (Astral)

ty is Astral's Rust type checker — "10x - 100x faster than mypy and
Pyright" ([ty docs](https://docs.astral.sh/ty/)) — but it is **beta**:
"Today, we're announcing the Beta release of ty [...] we're working
towards a Stable release next year" ([ty blog](https://astral.sh/blog/ty),
posted 2025; "next year" = 2026). The blog does not mention strict mode;
the absence of a strict bundle is established below from ty's own rules
reference, not the blog. Treat ty as a complementary second opinion, not a
mypy replacement:

- **No strict-mode parity.** ty has configurable rule *levels*
  (`error`/`warn`/`ignore`) but no `--strict` bundle equivalent and no
  rule that requires annotations on every function
  ([ty rules](https://docs.astral.sh/ty/reference/rules/)). So it cannot
  enforce a strict-defs contract — mypy remains the gate.
- **Different defaults and narrowing.** ty checks all code by default
  (including untyped), and its design centers the "gradual guarantee":
  adding annotations to working code never introduces new errors
  ([ty docs](https://docs.astral.sh/ty/)). Its narrowing and reachability
  analysis differ from mypy's, so the two can legitimately disagree — a ty
  finding is a prompt to investigate, not an automatic mypy bug.
- **No plugin system** (and no plans for one), so ty can't replace mypy
  where ORM/Pydantic plugins matter
  ([ty github](https://github.com/astral-sh/ty)). Irrelevant if you use no
  mypy plugins, but check before adopting ty anywhere.
- **Suppression syntax differs.** ty understands standard
  `# type: ignore`, plus its own `# ty: ignore[code]` and
  `# type: ignore[ty:code]`
  ([ty rules](https://docs.astral.sh/ty/reference/rules/)). A code that
  matches no known rule suppresses nothing.
- **DO run ty alongside mypy** (wire it as a preview under `[tool.ty]`):
  green-on-both raises confidence; a divergence is a signal to read both
  tools' reasoning. ty's stricter narrowing legitimately catches some
  `Any`-laundering holes mypy passes, so it earns more than a manual probe.
  **DO gate on ty *in addition to* mypy** when its version is pinned (a
  locked beta can't break the build spontaneously — only on a deliberate
  bump, where a genuine false positive is suppressed narrowly with
  `# ty: ignore[code]`, not by dropping the gate). **DON'T** gate on ty
  *alone*, or drop mypy for it — it has no strict-defs contract (above).

## Practical gotchas

- **Third-party stubs.** For libraries shipping no inline types, install
  the `types-*` stub package (e.g. `types-requests`); mypy emits
  `import-untyped` / `no-any-unimported` otherwise. A stdlib-only project
  needs no stubs — but don't paper over a missing stub with a module-level
  `ignore_missing_imports` override when a `types-*` package exists.
- **Flat modules vs namespace packages.** With no `__init__.py` (a flat
  source dir), mypy resolves imports via `mypy_path`, pytest via
  `pythonpath` + `--import-mode=importlib`. `namespace_packages`
  defaults to `True` (PEP 420)
  ([config_file.html](https://mypy.readthedocs.io/en/stable/config_file.html)).
  Keep the path settings of each tool (mypy `mypy_path`, pytest
  `pythonpath`, ty `extra-paths`) in sync — they should all point at the
  same source dir; drift breaks one tool silently. The exception is the test
  directory: pytest's `pythonpath` also carries `tests` (so test files can
  `from conftest import …` under importlib mode), and mypy's `mypy_path` and
  ty's `extra-paths` do not need it. Avoid same-named modules
  in two unpackaged dirs: importlib mode can't disambiguate them.
- **`warn_redundant_casts`** (in `--strict`) flags casts that change
  nothing; treat its findings as "delete the cast," not "add an ignore."
- **`no_implicit_reexport`** (in `--strict`) means a name imported into a
  module is NOT re-exported unless imported via `from ... import x as x`
  or listed in `__all__`
  ([command_line.html](https://mypy.readthedocs.io/en/stable/command_line.html)).
  If a test imports a helper that another module merely re-imported,
  expect an `attr-defined` error — fix the source module's `__all__`,
  don't suppress.

## Sources

- [mypy command line](https://mypy.readthedocs.io/en/stable/command_line.html)
- [mypy config file](https://mypy.readthedocs.io/en/stable/config_file.html)
- [mypy common issues](https://mypy.readthedocs.io/en/stable/common_issues.html)
- [ruff FAQ](https://docs.astral.sh/ruff/faq/)
- [ruff TC001](https://docs.astral.sh/ruff/rules/typing-only-first-party-import/)
- [ty docs](https://docs.astral.sh/ty/)
- [ty rules reference](https://docs.astral.sh/ty/reference/rules/)
- [ty launch blog](https://astral.sh/blog/ty)
- [ty github](https://github.com/astral-sh/ty)
