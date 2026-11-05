"""The three paths `write-guard.sh` judges a write on.

Each is NUL-terminated: where the write lands, where this project's sentinel
lands, and the given path normalised without following links.

Not an inline `python3 -c` because, with it in `write-guard.sh`, the plugin
directory's portal refused the plugin: docs/design/the-write-path.md. Inline
programs in other scripts passed that portal and need not move.
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
