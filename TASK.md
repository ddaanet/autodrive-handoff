## Current task

Merge `line-cap-split` into `dev`, proposed on 2026-10-31 with a default of yes
and not objected to. Release 0.19.0 is out from `main`, and the branch's review
against `dev` is triaged, its one medium fixed on the branch. `dev` is two
commits behind `main`: the README fix and the release bump. First action:
commit this frame on `line-cap-split`, since an uncommitted `TASK.md` and
`TODO.md` block the checkout; then check out `dev`, fast-forward it to `main`,
merge `line-cap-split` with `TASK.md` and `TODO.md` resolved to the branch's
side, and run `just precommit` before committing the merge.
