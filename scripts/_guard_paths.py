"""The three paths `write-guard.sh` judges a write on.

Each is NUL-terminated: where the write lands, where this project's sentinel
lands, and the given path normalised without following links.

A file rather than an inline `python3 -c`: the plugin directory's validator
refuses a hook script holding that program (docs/design/the-write-path.md).
"""

import os
import sys

given, sentinel = sys.argv[1:]
for path in (
    os.path.realpath(given),
    os.path.realpath(sentinel),
    os.path.normpath(os.path.abspath(given)),  # noqa: PTH100 - lexical: must not follow links
):
    sys.stdout.write(path + "\0")
