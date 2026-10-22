# shellcheck shell=bash
#
# Sourced by check-refs.sh, never run on its own: the Markdown reader, extract,
# and the existence test over the git listing, classify. Both are awk, under
# LC_ALL=C, written to POSIX awk so that mawk, gawk and the BSD awk on macOS
# read them alike.

# extract <dir>: reads one Markdown file on stdin and prints one line per
# reference, "line TAB target-as-written TAB path-from-the-root", the path
# normalised lexically ("." for the root). Under LC_ALL=C so that %XX decodes
# to the byte, not to a code point.
extract() {
    CHECK_REFS_DIR="$1" LC_ALL=C awk '
    BEGIN { dir = ENVIRON["CHECK_REFS_DIR"]; fence = 0; span = 0; comment = 0; hexd = "0123456789abcdef" }
    {
        line = $0
        sub(/\r$/, "", line)
        if (fence > 0) {
            if (closes_fence(line)) fence = 0
            next
        }
        if (comment) {
            i = index(line, "-->")
            if (i == 0) next
            line = substr(line, i + 3)
            comment = 0
        }
        if (opens_fence(line)) { span = 0; next }
        if (line ~ /^[ \t]*$/) { span = 0; next }
        text = strip_comments(strip_spans(line))
        if (match(text, /^ ? ? ?\[[^]^][^]]*\]:/)) {
            rest = substr(text, RSTART + RLENGTH)
            t = target_of(rest)
            if (t != "" && title_ok(after)) emit(t)
            next
        }
        while ((i = index(text, "](")) > 0) {
            escaped = (i > 1 && substr(text, i - 1, 1) == "\\")
            text = substr(text, i + 2)
            if (!escaped) emit(target_of(text))
        }
    }
    # strip_comments: the text with each HTML comment removed. One left open
    # hides the rest of the line and, through `comment`, the lines up to -->.
    function strip_comments(s,   out, i, j) {
        out = ""
        while ((i = index(s, "<!--")) > 0) {
            out = out substr(s, 1, i - 1) " "
            s = substr(s, i + 4)
            j = index(s, "-->")
            if (j == 0) { comment = 1; return out }
            s = substr(s, j + 3)
        }
        return out s
    }
    # A fence is a run of three or more backticks or tildes at the start of a
    # line, after any indent, so a fence inside a list item counts.
    function opens_fence(s,   c, n) {
        sub(/^[ \t]*/, "", s)
        c = substr(s, 1, 1)
        if (c != "`" && c != "~") return 0
        n = run_len(s, 1, c)
        if (n < 3) return 0
        # A backtick fence never has a backtick after its run: that is a span.
        if (c == "`" && index(substr(s, n + 1), "`") > 0) return 0
        fence = n; fence_char = c
        return 1
    }
    function closes_fence(s,   n) {
        sub(/^[ \t]*/, "", s)
        if (substr(s, 1, 1) != fence_char) return 0
        n = run_len(s, 1, fence_char)
        if (n < fence) return 0
        return substr(s, n + 1) ~ /^[ \t]*$/
    }
    function run_len(s, i, c,   n) {
        n = 0
        while (substr(s, i + n, 1) == c) n++
        return n
    }
    # strip_spans: the line with each inline code span blanked. A span left
    # open carries to the next line of the paragraph in `span`.
    function strip_spans(s,   out, i, n, rest, j) {
        out = ""
        if (span > 0) {
            j = find_run(s, span)
            if (j == 0) return ""
            s = substr(s, j + span)
            span = 0
        }
        while ((i = index(s, "`")) > 0) {
            out = out substr(s, 1, i - 1) " "
            n = run_len(s, i, "`")
            rest = substr(s, i + n)
            j = find_run(rest, n)
            if (j == 0) { span = n; return out }
            s = substr(rest, j + n)
        }
        return out s
    }
    # find_run: where a run of exactly n backticks starts in s, or 0.
    function find_run(s, n,   p, k, m) {
        p = 1
        while ((k = index(substr(s, p), "`")) > 0) {
            k = p + k - 1
            m = run_len(s, k, "`")
            if (m == n) return k
            p = k + m
        }
        return 0
    }
    # target_of: the destination at the start of s; sets `after` to the rest.
    function target_of(s,   t, i, c, depth) {
        sub(/^[ \t]*/, "", s)
        if (substr(s, 1, 1) == "<") {
            i = index(s, ">")
            if (i == 0) { after = ""; return "" }
            after = substr(s, i + 1)
            return substr(s, 2, i - 2)
        }
        depth = 0
        for (i = 1; i <= length(s); i++) {
            c = substr(s, i, 1)
            if (c == " " || c == "\t") break
            if (c == "(") depth++
            if (c == ")") { if (depth == 0) break; depth-- }
        }
        after = substr(s, i)
        return substr(s, 1, i - 1)
    }
    # A definition is followed by nothing or a title; "[x]: some prose" is not one.
    function title_ok(s,   c) {
        sub(/^[ \t]*/, "", s)
        c = substr(s, 1, 1)
        return s == "" || c == "\"" || c == "(" || c == sprintf("%c", 39)
    }
    function emit(raw,   p, k) {
        if (raw == "" || raw ~ /^[A-Za-z][A-Za-z0-9+.-]*:/) return
        if (substr(raw, 1, 1) == "#" || substr(raw, 1, 1) == "/") return
        p = raw
        k = index(p, "#")
        if (k > 0) p = substr(p, 1, k - 1)
        p = decode(p)
        if (p == "") return
        if (dir != "") p = dir "/" p
        print NR "\t" raw "\t" normalise(p)
    }
    function decode(s,   out, h) {
        out = ""
        while (match(s, /%[0-9A-Fa-f][0-9A-Fa-f]/)) {
            h = (index(hexd, tolower(substr(s, RSTART + 1, 1))) - 1) * 16 \
                + index(hexd, tolower(substr(s, RSTART + 2, 1))) - 1
            out = out substr(s, 1, RSTART - 1) (h == 0 ? "%00" : sprintf("%c", h))
            s = substr(s, RSTART + 3)
        }
        return out s
    }
    function normalise(p,   parts, n, i, stack, sp, out) {
        n = split(p, parts, "/")
        sp = 0
        for (i = 1; i <= n; i++) {
            if (parts[i] == "" || parts[i] == ".") continue
            if (parts[i] == ".." && sp > 0 && stack[sp] != "..") { sp--; continue }
            stack[++sp] = parts[i]
        }
        if (sp == 0) return "."
        out = stack[1]
        for (i = 2; i <= sp; i++) out = out "/" stack[i]
        return out
    }
    '
}

# classify <members> <dirs> <refs>: each reference record with a status field
# appended: ok (listed, or a directory holding a listed path, or the root), up
# (above the root), disk (inside a listed directory; the disk decides) or miss.
classify() {
    LC_ALL=C awk -F '\t' -v OFS='\t' '
    FILENAME == ARGV[1] { add($0); next }
    FILENAME == ARGV[2] { dir[$0] = 1; add($0); next }
    {
        res = $6
        if (res == ".") st = "ok"
        else if (res == ".." || substr(res, 1, 3) == "../") st = "up"
        else if (res in member) st = "ok"
        else if (in_dir(res)) st = "disk"
        else st = "miss"
        print $0, st
    }
    # add: the path and every directory above it are members.
    function add(p,   n, parts, i, q) {
        member[p] = 1
        n = split(p, parts, "/")
        q = parts[1]
        for (i = 2; i <= n; i++) { member[q] = 1; q = q "/" parts[i] }
    }
    function in_dir(p,   n, parts, i, q) {
        n = split(p, parts, "/")
        q = parts[1]
        for (i = 2; i <= n; i++) { if (q in dir) return 1; q = q "/" parts[i] }
        return 0
    }
    ' "$1" "$2" "$3"
}
