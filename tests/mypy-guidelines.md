# mypy guidelines — review checklist

Engineering-grade rules for type-checking Python with mypy (plus ruff and
ty). Phrased as checkable DO/AVOID rules so code can be audited against
them. Each non-obvious claim cites a primary source inline.

Verified against mypy **2.1.0** stable. mypy **2.0** changed two defaults
that matter here (`--strict-bytes`, `local_partial_types`), so a project
on a `mypy>=1.x` floor that nonetheless resolves a 2.x interpreter still
sees the 2.x behavior — pin the version if you depend on either. Sources
are listed at the bottom; URLs are also inlined at each claim.

Suppression debt, the ruff and ty comparisons and the practical gotchas are in
[mypy-suppressions-and-tooling.md](mypy-suppressions-and-tooling.md).

## Strict mode

`--strict` is a bundle, not a single check. As of mypy 2.1 it enables:
`--disallow-any-generics`, `--disallow-subclassing-any`,
`--disallow-untyped-calls`, `--disallow-untyped-defs`,
`--disallow-incomplete-defs`, `--check-untyped-defs`,
`--disallow-untyped-decorators`, `--warn-redundant-casts`,
`--warn-unused-ignores`, `--warn-return-any`, `--no-implicit-reexport`,
`--strict-equality`, and `--extra-checks`
([command_line.html](https://mypy.readthedocs.io/en/stable/command_line.html)).
The exact set grows across releases, so pin the mypy version if you depend
on the bundle's contents. mypy **2.0** also made `--strict-bytes` a
default (independent of `--strict`): `bytearray`/`memoryview` are no longer
implicitly assignable to `bytes` (PEP 688)
([mypy 2.0 release](https://mypy-lang.blogspot.com/2026/05/mypy-20-relased.html)).

A few bundle members are worth calling out as *checkable rules* in their
own right, since an audit pass should know what they catch:

- **`disallow_any_generics`** — "disallows usage of generic types that do
  not specify explicit type parameters"
  ([command_line.html](https://mypy.readthedocs.io/en/stable/command_line.html)).
  This is the rule that forces `dict[str, Any]` instead of a bare `dict`,
  and is why a JSON-entry alias is spelled `Json = dict[str, Any]` rather
  than `Json = dict`. **DO write fully-parameterised generics** (`list[str]`,
  `dict[str, Any]`, `Sequence[int]`); a bare `list`/`dict`/`tuple` in an
  annotation is a finding under strict.
- **`strict_equality`** — "prohibit[s] [...] comparisons of non-overlapping
  types" so `42 == "no"` (always-false) is an error
  ([command_line.html](https://mypy.readthedocs.io/en/stable/command_line.html)).
  **DO treat a `strict-equality` finding as a real bug** (mismatched
  operands), not noise to suppress.
- **`warn_return_any`** — warns "when returning a value with type `Any`
  from a function declared with a non-`Any` return type"
  ([command_line.html](https://mypy.readthedocs.io/en/stable/command_line.html)).
  This is the strict member that bites JSON-parsing code: `json.loads(...)`
  is `Any`, so returning it from a `-> Entry` function trips the warning.
  **DO narrow (or annotate the intermediate)** rather than suppress.
- **`no_implicit_optional` is on by default** (since mypy 0.980, not a
  strict member): a `None` default no longer implies `T | None`
  ([command_line.html](https://mypy.readthedocs.io/en/stable/command_line.html)).
  **DO write the Optional explicitly** — `def f(x: str | None = None)`,
  never `def f(x: str = None)`.

Configuration and opt-in rules around the bundle:

- **DO set `strict = true`.** It is the floor, not the ceiling. With it,
  "you will basically never get a type related error at runtime without a
  corresponding mypy error, unless you explicitly circumvent mypy"
  ([getting_started.html](https://mypy.readthedocs.io/en/stable/getting_started.html)).
- **DO add `warn_unreachable`** on top of strict — it is NOT in the
  bundle. It "report[s] an error whenever it encounters code determined to
  be unreachable or redundant after performing type analysis"
  ([command_line.html](https://mypy.readthedocs.io/en/stable/command_line.html)),
  which surfaces dead branches left by over-narrow annotations. Caveat: it
  reasons over types, not values, so it can't see value-level dead code,
  and `if TYPE_CHECKING`/version guards can trip it — suppress those
  narrowly, don't disable the flag
  ([Adam Johnson](https://adamj.eu/tech/2021/05/19/python-type-hints-mypy-unreachable-code-detection/)).
- **CONSIDER `disallow_any_explicit`** — it "disallows explicit `Any` in
  type positions such as type annotations and generic type parameters"
  ([command_line.html](https://mypy.readthedocs.io/en/stable/command_line.html)).
  Tradeoff: it bans the deliberate `Any` escape hatch entirely, so it only
  pays off in code with no genuinely-dynamic boundary. For JSON-parsing
  code it is usually too blunt; prefer typing the boundary (below) over a
  global ban.
- **CONSIDER opt-in optional codes** beyond strict, each via
  `enable_error_code`: `redundant-expr` (always-true/false expressions),
  `truthy-bool` (objects without `__bool__`/`__len__` in a boolean
  context), `possibly-undefined` (var maybe-unset on some path),
  `explicit-override` (require `@override`). All are off by default and
  must be enabled explicitly
  ([error_code_list2.html](https://mypy.readthedocs.io/en/stable/error_code_list2.html)).
- **`extra_checks`** is already inside `--strict`; setting it again is
  harmless but redundant. It "enables additional checks that are
  technically correct but may be impractical," e.g. prohibiting partial
  overlap in `TypedDict` updates
  ([command_line.html](https://mypy.readthedocs.io/en/stable/command_line.html)).

## Config hygiene

- **DO use `files`/`mypy_path`** for a flat-module layout (no package, no
  `__init__.py`). `mypy_path` "specifies the paths to use, after trying
  the paths from MYPYPATH" and "may only be set in the global section"
  ([config_file.html](https://mypy.readthedocs.io/en/stable/config_file.html)).
  This is how modules in a flat source dir resolve without a package
  prefix — mirroring pytest's `pythonpath`. Use `packages =` only for real
  importable packages with `__init__.py`.
- **AVOID per-module `[[tool.mypy.overrides]]` that loosen strictness**
  unless the relaxation is forced by a third party you don't control.
  A self-authored module that needs `disallow_untyped_defs = false` is a
  code smell — fix the annotations instead. Override precedence is
  inline > per-module > global
  ([config_file.html](https://mypy.readthedocs.io/en/stable/config_file.html)),
  so an override silently masks the global strict setting; keep them
  greppable and commented with the reason.
- **AVOID `disable_error_code` at config level** for anything but a
  documented, whole-codebase exemption. Disabling a code globally hides
  every future instance, including new bugs. Prefer a line-level
  `# type: ignore[code]` so the suppression is local and visible
  ([config_file.html](https://mypy.readthedocs.io/en/stable/config_file.html)).
- **KNOW that `exclude` only affects recursive *discovery*, not paths
  given explicitly.** Per the docs, `exclude` is "A regular expression that
  matches file names, directory names and paths which mypy should ignore
  while recursively discovering files to check"
  ([config_file.html](https://mypy.readthedocs.io/en/stable/config_file.html));
  a file passed on the command line, or pulled in via `files`/import
  resolution, is still checked even if it matches `exclude` (mypy
  [#11760](https://github.com/python/mypy/issues/11760)). Rule: if a
  file you expected to be skipped is still type-checked, it's reachable via
  `files`/`mypy_path` — narrow `files` rather than expecting `exclude` to
  override it. (`force_exclude` exists for the discovery case but is not
  needed when files are listed explicitly.)
- **For gradual adoption** (introducing strict mypy into an untyped
  codebase), don't flip `strict = true` globally on day one. Start with the
  default (lenient) config, then ratchet: enable one strict sub-flag at a
  time, or scope strictness to already-clean modules via a per-module
  override that *raises* strictness (the inverse of the loosening overrides
  warned against above), then widen
  ([config_file.html](https://mypy.readthedocs.io/en/stable/config_file.html)).
  A small, already-strict codebase needs none of this; the ratchet is for
  introducing strict mypy into a large untyped codebase.
- **`local_partial_types`** prevents inferring a variable's type from an
  empty container that is later filled in another scope, and "must be
  enabled when using the mypy daemon"
  ([config_file.html](https://mypy.readthedocs.io/en/stable/config_file.html)).
  As of **mypy 2.0 it is enabled by default**; explicitly disabling it is
  still supported "for now" but "this support will be removed in the
  future"
  ([mypy 2.0 release](https://mypy-lang.blogspot.com/2026/05/mypy-20-relased.html)).
  DO keep it on (or rely on the default); never set `no_local_partial_types`.
- **`allow_redefinition_new`** was the mypy 1.16–1.20 experimental name
  for flexible redefinition (redefine a variable at a different type;
  infer a union from multiple assignments)
  ([changelog](https://mypy.readthedocs.io/en/stable/changelog.html)). In
  **mypy 2.0 the plain `--allow-redefinition` adopted that behavior**, the
  old behavior moved to `--allow-redefinition-old`, and on 2.x docs
  `allow_redefinition_new` is now a **deprecated alias**
  ([mypy 2.0 release](https://mypy-lang.blogspot.com/2026/05/mypy-20-relased.html),
  [config_file.html](https://mypy.readthedocs.io/en/stable/config_file.html)).
  The new behavior requires `local_partial_types`. **DO migrate the config
  key to `allow_redefinition = true`** once on mypy ≥ 2.0.

## Annotation practices

- **DO type JSON-shaped data at the boundary, not with bare
  `dict[str, Any]` everywhere.** For dicts with a known, fixed key set use
  a `TypedDict`: unlike `dict[str, Any]` it lets the checker catch
  undefined-key access and wrong value types at dev time
  ([typing spec: TypedDict](https://typing.python.org/en/latest/spec/typeddict.html)).
  Use `total=False` (all keys optional) or per-key `NotRequired[...]` for
  partially-present payloads. Note TypedDict values must be a real `dict`,
  not a subclass.
- **WHEN the JSON shape is open/unknown** (arbitrary keys, untrusted
  external transcript format that "evolves"), a bare `dict[str, Any]` or a
  type alias at the parse boundary is the honest annotation — `Any` here is
  a real boundary, not a hole. A commented alias such as
  `Json = dict[str, Any]  # undocumented, evolving format` parameterises the
  generic (satisfying `disallow_any_generics`) while owning the `Any` as a
  deliberate, documented boundary. Narrow to concrete types as soon as you
  read a field. **DO comment the alias** so the `Any` reads as intentional,
  not lazy.

### Prefer structured types over primitives

Bare `dict[str, Any]` and bare string constants are the two places a
strict checker goes blind. Reach for a structured type before a primitive;
pick the lightest one that buys real checking. The gradient, lightest to
heaviest:

- **`Literal[...]` / `Enum` for a fixed set of string (or int) constants.**
  When a field has a closed value set — e.g. a tool name `"Write" | "Edit"`,
  a block `type` of `"tool_use" | "text" | "tool_result"` — annotate it as
  `Literal["Write", "Edit"]` (or an `enum.Enum`) instead of `str`. The
  checker then catches a typo'd or stale comparison (`block["name"] ==
  "Wrtie"`) and exhaustiveness gaps that a bare `str` waves through; mypy
  has dedicated Literal and Enum narrowing
  ([literal_types.html](https://mypy.readthedocs.io/en/stable/literal_types.html)).
  Prefer `Literal` for ad-hoc closed sets, `Enum` when the set has a name,
  members worth referencing, or behavior. **AVOID raw magic-string
  comparisons** like `name not in ("Write", "Edit")` scattered across a
  module — hoist to a `Literal`/`Enum` or at least a named constant so a
  rename is one edit and a typo is a type error. Caveat: when the
  surrounding dict stays `Any` at the boundary, a `Literal` annotation on a
  value read from it is erased on contact (mypy won't check `Any` against a
  `Literal`), so the realisable win is often just the de-duplication of a
  named constant, not new checking — weigh the heavier `Literal`/`Enum`
  against that before reaching for it.
- **`TypedDict` for a JSON object with a known, fixed key set** (see the
  bullet above) — the apt, zero-runtime structural fit for decoded JSON.
  It models "a `dict` with these keys/value-types" without a parse step, so
  it's the natural upgrade from `dict[str, Any]` when the shape is known.
- **`@dataclass` (or `NamedTuple`) when you construct/parse into objects**
  rather than passing dicts around. A dataclass implies a parse boundary
  (`Entry(**d)` or a `from_json`); in return mypy checks attribute access,
  `__init__` signatures, and (frozen) immutability
  ([additional_features.html](https://mypy.readthedocs.io/en/stable/additional_features.html#dataclasses)).
  Choose this over TypedDict when you want methods, defaults, or identity —
  not merely structural dict access.
- **pydantic when you need runtime validation at a boundary** (untrusted
  input, config, API payloads). It's the strongest — it *enforces* the
  types at runtime, and its mypy plugin tightens model signatures
  ([pydantic mypy plugin](https://docs.pydantic.dev/latest/integrations/mypy/)).
  But it is a **third-party runtime dependency**. Weigh that against the
  context: in an application, often worth it; in a stdlib-only script with
  no runtime deps by design, it's the heaviest option and likely overkill —
  a `TypedDict` + narrowing carries no dependency.

The rule of thumb: **`Literal`/`Enum` for constants, `TypedDict` for known
JSON shapes, `dataclass` when you parse, pydantic when you must validate.**
Default toward the lightest that removes the `Any`/magic-string blind spot.

- **PREFER `object` over `Any` when you accept anything but won't operate
  on it blindly.** `object` "only supports operations defined for _all_
  objects, such as equality and isinstance()"; `Any` "supports all
  operations, even if they may fail at runtime"
  ([common_issues.html](https://mypy.readthedocs.io/en/stable/common_issues.html)).
  `object` forces a narrowing step; `Any` silently disables checking.
- **DO narrow with `isinstance` / `assert isinstance`** rather than
  `cast`. Mypy infers types after an `isinstance` check, and "you can use
  an `assert` statement together with [...] type inference techniques" to
  narrow (`assert isinstance(found, str)`)
  ([common_issues.html](https://mypy.readthedocs.io/en/stable/common_issues.html)).
  An `assert` also fails loudly at runtime if the invariant breaks; a
  `cast` does not.
- **AVOID `cast` except where narrowing genuinely cannot reach.** `cast`
  bypasses type safety with zero runtime check — mypy trusts it blindly
  ([common_issues.html](https://mypy.readthedocs.io/en/stable/common_issues.html)).
  With `warn_redundant_casts` (in `--strict`) mypy will at least flag a
  cast that does nothing. Every `cast` deserves a comment justifying why
  narrowing was impossible.
- **DO annotate test functions `-> None`.** Under `--strict`,
  `disallow_untyped_defs` requires it; an un-annotated `def test_x():` is
  an untyped def and mypy will flag it. Keep the whole test suite annotated.
- **DON'T let an untyped decorator erase a function's signature.**
  `disallow_untyped_decorators` (in `--strict`) flags decorating a typed
  function with an untyped decorator
  ([command_line.html](https://mypy.readthedocs.io/en/stable/command_line.html)),
  because an untyped decorator makes the decorated function `Any`,
  silently dropping its annotations. For pytest, `@pytest.fixture` and
  `@pytest.mark.*` are typed in modern `pytest` (≥8), so this should not
  fire; if it does, the fix is a properly-typed decorator, not a per-line
  ignore.
- **USE `reveal_type(expr)` to debug inference, then delete it.** mypy
  prints the static type of `expr` at that point (no import needed at
  type-check time)
  ([common_issues.html](https://mypy.readthedocs.io/en/stable/common_issues.html)).
  It's the fastest way to see why a narrowing didn't take. Enable the
  optional `unimported-reveal` code if you want mypy to *require* importing
  `reveal_type`, so a stray debug call can't ship
  ([error_code_list2.html](https://mypy.readthedocs.io/en/stable/error_code_list2.html)).

## Sources

- [mypy command line](https://mypy.readthedocs.io/en/stable/command_line.html)
- [mypy config file](https://mypy.readthedocs.io/en/stable/config_file.html)
- [mypy getting started](https://mypy.readthedocs.io/en/stable/getting_started.html)
- [mypy optional error codes](https://mypy.readthedocs.io/en/stable/error_code_list2.html)
- [mypy common issues](https://mypy.readthedocs.io/en/stable/common_issues.html)
- [mypy changelog](https://mypy.readthedocs.io/en/stable/changelog.html)
- [mypy 2.0 release blog](https://mypy-lang.blogspot.com/2026/05/mypy-20-relased.html)
- [mypy #11760 — exclude vs explicit files](https://github.com/python/mypy/issues/11760)
- [typing spec: TypedDict](https://typing.python.org/en/latest/spec/typeddict.html)
- [Adam Johnson — unreachable code detection](https://adamj.eu/tech/2021/05/19/python-type-hints-mypy-unreachable-code-detection/)
