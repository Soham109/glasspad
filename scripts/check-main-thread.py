#!/usr/bin/env python3
"""Fails when code that runs on the main thread makes a call that can block it.

The menu bar icon froze once because the Automation permission check ran on the main thread.
This keeps that, and its relatives, from coming back: in every main actor code path of the
apps and packages (types marked @MainActor or built on AppKit, UIKit and SwiftUI types,
functions marked @MainActor, closures sent to the main queue) it looks for

    AEDeterminePermissionToAutomateTarget, waitUntilExit, a semaphore or group wait,
    Thread.sleep, sleep and usleep

either written there directly, or one call away (a synchronous function elsewhere whose body
makes one of those calls outside a background closure). Closures sent to a background queue,
a detached task or a new thread, and nonisolated functions, are skipped.

Reviewed exceptions live in scripts/main-thread-allowlist.txt, one per line:
    <path>|<enclosing function>|<call>   # why it is safe

Usage: scripts/check-main-thread.py [repo root]       (exit 1 when something is found)
       scripts/check-main-thread.py --self-test
"""
import os
import re
import sys

SOURCE_DIRS = ["Apps/Mac/Sources", "Apps/iOS/Sources", "Apps/iOS/Shared", "Apps/iOS/Widgets"]
PACKAGE_SOURCES = "Packages"

BLOCKING = [
    ("AEDeterminePermissionToAutomateTarget", re.compile(r"\bAEDeterminePermissionToAutomateTarget\s*\(")),
    ("waitUntilExit", re.compile(r"\.waitUntilExit\s*\(")),
    ("wait()", re.compile(r"\.wait\s*\(\s*(timeout\s*:[^)]*|wallTimeout\s*:[^)]*)?\)")),
    ("Thread.sleep", re.compile(r"\bThread\.sleep\s*\(")),
    ("sleep", re.compile(r"(?<![\w.])u?sleep\s*\(\s*\d")),
]

# Types whose members run on the main actor (SwiftUI, AppKit, UIKit).
MAIN_BASES = {
    "View", "App", "Scene", "ViewModifier", "Commands", "NSViewRepresentable", "UIViewRepresentable",
    "NSViewControllerRepresentable", "UIViewControllerRepresentable",
    "NSApplicationDelegate", "UIApplicationDelegate", "UIWindowSceneDelegate", "UISceneDelegate",
    "NSViewController", "NSWindowController", "NSView", "NSWindow", "NSPanel", "NSControl", "NSButton",
    "NSMenu", "NSMenuItem", "NSStatusItem", "NSHostingView", "NSHostingController", "NSPopover",
    "NSWindowDelegate", "NSMenuDelegate", "NSPopoverDelegate", "NSTextFieldDelegate", "NSTableViewDelegate",
    "NSTableViewDataSource", "UIViewController", "UIView", "UIHostingController", "UIControl",
    "UIGestureRecognizer", "UIGestureRecognizerDelegate", "UIScrollViewDelegate", "UITextFieldDelegate",
}

# Closures handed to these run somewhere other than the caller's thread.
BACKGROUND_TAIL = re.compile(
    r"(DispatchQueue\.global\s*\([^)]*\)\s*\.(async|asyncAfter)\b[^{]*$)"
    r"|(\b(queue|Queue|q|workQueue|ioQueue|background)\w*\s*\.(async|asyncAfter)\b[^{]*$)"
    r"|(DispatchQueue\s*\(\s*label[^{]*\.(async|asyncAfter)\b[^{]*$)"
    r"|(Task\.detached\b[^{]*$)|(\bThread\s*(\(\s*block\s*:)?\s*$)|(detachNewThread\b[^{]*$)"
    r"|(\b\w*[Hh]andler\s*=\s*$)|(concurrentPerform\b[^{]*$)|(\.addOperation\s*$)"
    # A closure handed to an injected queue (`restartQueue { ... }`).
    r"|(\b\w*Queue\s*$)"
)
MAIN_TAIL = re.compile(r"(DispatchQueue\.main\.(async|asyncAfter|sync)\b[^{]*$)|(MainActor\.run\b[^{]*$)|(MainActor\.assumeIsolated\b[^{]*$)")
TYPE_DECL = re.compile(r"\b(class|struct|enum|extension|actor|protocol)\s+([A-Za-z_][\w.]*)([^{]*)$")
FUNC_DECL = re.compile(r"\bfunc\s+([A-Za-z_]\w*|[^\s(<]+)\s*(<[^>]*>)?\s*\((.*)$", re.S)
INIT_DECL = re.compile(r"\b(init[?!]?|deinit|subscript)\b\s*(<[^>]*>)?\s*(\((.*))?$", re.S)
ACCESSOR = re.compile(r"\b(var)\s+\w+\s*:[^=]*$|^\s*(get|set|didSet|willSet|_modify|_read)\b")


def strip(src):
    """Blanks out comments and string contents, keeping every newline (and so line numbers)."""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith("//", i):
            j = src.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
        elif src.startswith("/*", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if src.startswith("/*", j):
                    depth, j = depth + 1, j + 2
                elif src.startswith("*/", j):
                    depth, j = depth - 1, j + 2
                else:
                    j += 1
            out.append(re.sub(r"[^\n]", " ", src[i:j]))
            i = j
        elif c == '"' or (c == "#" and re.match(r'#+"', src[i:])):
            hashes = len(re.match(r"#*", src[i:]).group(0))
            start = i + hashes
            multi = src.startswith('"""', start)
            close = ('"""' if multi else '"') + "#" * hashes
            j = start + (3 if multi else 1)
            # Interpolations are kept so calls inside them still count.
            body = []
            while j < n and not src.startswith(close, j):
                if src[j] == "\\" and hashes == 0 and j + 1 < n and src[j + 1] != "(":
                    body.append("  " if src[j + 1] != "\n" else " \n")
                    j += 2
                    continue
                if src.startswith("\\" + "#" * hashes + "(", j):
                    k = j + 2 + hashes
                    depth = 1
                    seg = []
                    while k < n and depth:
                        if src[k] == "(":
                            depth += 1
                        elif src[k] == ")":
                            depth -= 1
                        seg.append(src[k])
                        k += 1
                    body.append(" " * (2 + hashes) + strip("".join(seg)))
                    j = k
                    continue
                body.append("\n" if src[j] == "\n" else " ")
                j += 1
            j = min(n, j + len(close))
            # The quotes stay, so an argument that is only a string still counts as one.
            out.append(" " * (start - i + (2 if multi else 0)) + '"' + "".join(body) + '"' + " " * (len(close) - 1))
            i = j
        else:
            out.append(c)
            i += 1
    text = "".join(out)
    assert text.count("\n") == src.count("\n")
    return text


def labels_of(params):
    """`_ a: Int, b c: String` -> ['_', 'b']: the argument labels a call uses."""
    depth, cur, parts = 0, "", []
    for ch in params:
        if ch in "([<{":
            depth += 1
        elif ch in ")]>}":
            if depth == 0:
                break
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        parts.append(cur)
    out = []
    for p in parts:
        head = p.split(":")[0].split()
        if not head:
            continue
        out.append(head[0])
    return out


def call_labels(args):
    depth, cur, parts = 0, "", []
    for ch in args:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            if depth == 0:
                break
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        parts.append(cur)
    out = []
    for p in parts:
        m = re.match(r"\s*([A-Za-z_]\w*)\s*:(?!:)", p)
        out.append(m.group(1) if m else "_")
    return out


class Scope:
    def __init__(self, kind, main, background, name=None, key=None, is_async=False, line=0, type_name=None, bases=()):
        self.kind, self.main, self.background, self.bases = kind, main, background, list(bases)
        self.name, self.key, self.is_async, self.line, self.type_name = name, key, is_async, line, type_name


def header_tail(text):
    """The declaration or statement that a `{` opens: its last line plus attribute lines and
    the earlier lines of a signature that runs over several lines."""
    lines = text.split("\n")
    while lines and not lines[-1].strip():
        lines.pop()
    if not lines:
        return ""
    tail = [lines.pop()]
    depth = tail[0].count(")") - tail[0].count("(")
    while lines:
        prev = lines[-1].strip()
        cont = (depth > 0 or prev.startswith("@") or prev.endswith((",", "(", "->", "=", "&&", "||"))
                or tail[0].strip().startswith((")", "->", "where", ".", ",", "async", "throws", "rethrows", "&&", "||", ":"))
                or re.fullmatch(r"(public|private|fileprivate|internal|open|final|static|class|override|nonisolated|"
                                r"@\w+(\([^)]*\))?|\s)+", prev or "x") is not None)
        if not cont:
            break
        line = lines.pop()
        depth += line.count(")") - line.count("(")
        tail.insert(0, line)
    return "\n".join(tail)


def bases_of(rest):
    m = re.match(r"\s*(<[^>]*>)?\s*:\s*([^{]*?)(\bwhere\b|$)", rest)
    if not m:
        return []
    return [re.sub(r"<.*", "", b).strip().split(".")[-1] for b in m.group(2).split(",") if b.strip()]


def scan(text, main_types):
    """Yields (event, data) for every scope opened, blocking call and call site."""
    stack = [Scope("file", False, False)]
    last = 0
    i, n = 0, len(text)
    line = 1
    events = []
    pos_line = [0] * (n + 1)
    for idx, ch in enumerate(text):
        pos_line[idx] = line
        if ch == "\n":
            line += 1
    pos_line[n] = line

    def record_calls(seg, offset):
        top = stack[-1]
        for name, rx in BLOCKING:
            for m in rx.finditer(seg):
                events.append(("block", name, pos_line[offset + m.start()], list(stack)))
        for m in re.finditer(r"(?<![\w])([A-Za-z_]\w*)\s*\(", seg):
            word = m.group(1)
            if word in {"if", "for", "while", "switch", "guard", "return", "func", "init", "catch", "case"}:
                continue
            events.append(("call", (word, call_labels(seg[m.end():])), pos_line[offset + m.start()], list(stack)))

    while i < n:
        ch = text[i]
        if ch == "{":
            seg = text[last:i]
            record_calls(seg, last)
            tail = header_tail(seg)
            parent = stack[-1]
            after = text[i + 1:i + 120]
            closure_main = re.match(r"\s*(\[[^\]]*\]\s*)?@MainActor\b", after) is not None
            td = TYPE_DECL.search(tail)
            fd = FUNC_DECL.search(tail)
            idl = INIT_DECL.search(tail)
            attrs_main = "@MainActor" in tail
            nonisolated = re.search(r"\bnonisolated\b", tail) is not None
            if td and not fd and td.group(1) != "protocol" and not re.search(r"\b(if|guard|while|for)\b", tail.split(td.group(1))[0]):
                kind, name = td.group(1), td.group(2).split(".")[-1]
                bases = bases_of(td.group(3))
                if kind == "actor":
                    s = Scope("type", False, True, type_name=name, bases=bases)
                else:
                    main = attrs_main or any(b in MAIN_BASES or b in main_types for b in bases) or \
                        (kind == "extension" and name in main_types)
                    s = Scope("type", main, False, type_name=name, bases=bases)
            elif fd or (idl and not re.search(r"=\s*$", tail)):
                if fd:
                    fname = fd.group(1)
                    key = (fname, labels_of(fd.group(3)))
                else:
                    fname = idl.group(1).rstrip("?!")
                    key = (fname, labels_of(idl.group(4) or ""))
                is_async = re.search(r"\)\s*(async)\b", tail) is not None
                inherit = parent.main if parent.kind == "type" else (parent.main if parent.kind != "file" else False)
                main = attrs_main or (inherit and not nonisolated)
                s = Scope("func", main, nonisolated or parent.background, name=fname, key=key,
                          is_async=is_async, line=pos_line[i], type_name=next((x.type_name for x in reversed(stack) if x.kind == "type"), None))
            elif ACCESSOR.search(tail.split("\n")[-1]) and parent.kind in ("type", "func") and "=" not in tail.split("\n")[-1].split(":")[-1]:
                main = attrs_main or (parent.main and not nonisolated)
                s = Scope("func", main, nonisolated, name=tail.split("\n")[-1].strip().split(":")[0], key=None,
                          line=pos_line[i], type_name=next((x.type_name for x in reversed(stack) if x.kind == "type"), None))
            else:
                last_line = tail.split("\n")[-1] if tail else ""
                if closure_main or MAIN_TAIL.search(last_line):
                    s = Scope("closure", True, False)
                elif BACKGROUND_TAIL.search(last_line):
                    s = Scope("closure", False, True)
                else:
                    s = Scope("block", parent.main, parent.background)
            stack.append(s)
            events.append(("open", s, pos_line[i], list(stack)))
            last = i + 1
        elif ch == "}":
            record_calls(text[last:i], last)
            if len(stack) > 1:
                stack.pop()
            last = i + 1
        i += 1
    record_calls(text[last:], last)
    return events


def enclosing_func(stack):
    for s in reversed(stack):
        if s.kind == "func":
            return s
    return None


def in_main(stack):
    """Main thread code: the innermost scope says main and nothing between it and here moved
    the work off the main thread."""
    for s in reversed(stack):
        if s.background:
            return False
        if s.kind in ("closure", "func", "type"):
            return s.main
    return False


def blocks_caller(stack):
    """A blocking call that holds whoever called the function it is in."""
    for s in reversed(stack):
        if s.background:
            return None
        if s.kind == "func":
            return None if s.is_async else s
        if s.kind in ("type", "file"):
            return None
    return None


def check(root):
    files = []
    for d in SOURCE_DIRS:
        files += walk(os.path.join(root, d))
    pk = os.path.join(root, PACKAGE_SOURCES)
    if os.path.isdir(pk):
        for p in sorted(os.listdir(pk)):
            files += walk(os.path.join(pk, p, "Sources"))
    texts = {}
    for f in files:
        with open(f, encoding="utf-8", errors="replace") as fh:
            texts[f] = strip(fh.read())
    # Types marked @MainActor (or built on a main actor type), to a fixed point.
    main_types = set()
    decl = re.compile(r"(@MainActor[^{]*?)?\b(?:class|struct|enum|actor)\s+([A-Za-z_]\w*)([^{]*)\{")
    changed = True
    while changed:
        changed = False
        for t in texts.values():
            for m in decl.finditer(t):
                name = m.group(2)
                if name in main_types:
                    continue
                if (m.group(1) and "@MainActor" in m.group(1) and "\n\n" not in m.group(1)) or \
                        any(b in MAIN_BASES or b in main_types for b in bases_of(m.group(3))):
                    main_types.add(name)
                    changed = True
    found, blockers, calls = [], {}, []
    texts_by_rel = {os.path.relpath(f, root): t for f, t in texts.items()}
    for f, t in texts.items():
        rel = os.path.relpath(f, root)
        for kind, data, line, stack in scan(t, main_types):
            if kind == "block":
                fn = enclosing_func(stack)
                where = fn.name if fn else "(top level)"
                if in_main(stack):
                    found.append((rel, line, where, data, "directly"))
                else:
                    b = blocks_caller(stack)
                    if b is not None and b.key is not None:
                        # The type the function belongs to and what it conforms to: a call
                        # elsewhere can only reach it from a file that names one of them.
                        owner = next((s for s in reversed(stack) if s.kind == "type"), None)
                        names = [owner.type_name] + owner.bases if owner else []
                        blockers.setdefault((b.key[0], tuple(b.key[1])), []).append((rel, b.line, b.name, data, names))
            elif kind == "call" and in_main(stack):
                fn = enclosing_func(stack)
                calls.append((rel, line, fn.name if fn else "(top level)", data))
    for rel, line, where, (name, labels) in calls:
        for (bname, blabels), defs in blockers.items():
            if bname == name and list(blabels) == labels[:len(blabels)] and len(labels) == len(blabels):
                for drel, dline, _, what, names in defs:
                    if (drel, dline) == (rel, line):
                        continue
                    if drel != rel and not any(re.search(r"\b%s\b" % re.escape(x), texts_by_rel[rel]) for x in names):
                        continue
                    found.append((rel, line, where, what, f"through {name}() at {drel}:{dline}"))
    return sorted(set(found))


def walk(d):
    out = []
    if not os.path.isdir(d):
        return out
    for base, dirs, names in os.walk(d):
        dirs[:] = sorted(x for x in dirs if x not in (".build", "build"))
        out += [os.path.join(base, x) for x in sorted(names) if x.endswith(".swift")]
    return out


def allowlist(root):
    path = os.path.join(root, "scripts", "main-thread-allowlist.txt")
    entries = set()
    if os.path.exists(path):
        for raw in open(path, encoding="utf-8"):
            line = raw.split("#", 1)[0].strip()
            if line:
                parts = [p.strip() for p in line.split("|")]
                if len(parts) == 3:
                    entries.add(tuple(parts))
    return entries


def main(argv):
    if argv[1:2] == ["--self-test"]:
        return self_test()
    root = os.path.abspath(argv[1] if len(argv) > 1 else os.path.join(os.path.dirname(__file__), ".."))
    allowed = allowlist(root)
    problems = [p for p in check(root) if (p[0], p[2], p[3]) not in allowed]
    used = {(p[0], p[2], p[3]) for p in check(root)}
    for rel, line, where, what, how in problems:
        print(f"{rel}:{line}: {what} on the main thread in {where} ({how})")
    stale = sorted(allowed - used)
    for e in stale:
        print(f"note: allowlist entry no longer needed: {'|'.join(e)}")
    if problems:
        print(f"FAILED: {len(problems)} blocking call(s) on the main thread")
        return 1
    print("main thread: no blocking calls found")
    return 0


SELF_TESTS = [
    # (swift source, expected number of findings)
    ("@MainActor final class A { func f() { p.waitUntilExit() } }", 1),
    ("final class A { func f() { p.waitUntilExit() } }", 0),
    ("@MainActor final class A { nonisolated func f() { p.waitUntilExit() } }", 0),
    ("@MainActor final class A { func f() { DispatchQueue.global().async { p.waitUntilExit() } } }", 0),
    ("@MainActor final class A { func f() { Task.detached { Thread.sleep(forTimeInterval: 1) } } }", 0),
    ("@MainActor final class A { func f() { Task { Thread.sleep(forTimeInterval: 1) } } }", 1),
    ("final class A { func f() { DispatchQueue.main.async { sem.wait() } } }", 1),
    ("final class A { func f() { Task { @MainActor in sem.wait(timeout: .now() + 1) } } }", 1),
    ("struct V: View { var body: some View { let _ = usleep(10); return Text(\"\") } }", 1),
    ("struct V: View { var body: some View { Text(\"sleep(1) waitUntilExit()\") } }", 0),
    ("@MainActor\npublic final class A {\n    func f() {\n        // p.waitUntilExit()\n    }\n}", 0),
    ("final class R { func run(_ a: String, _ b: [String]) -> Int { p.waitUntilExit(); return 0 } }\n"
     "@MainActor final class A { let r = R(); func f() { _ = r.run(\"x\", [\"y\"]) } }", 1),
    ("final class R { func run(_ a: String) async -> Int { p.waitUntilExit(); return 0 } }\n"
     "@MainActor final class A { func f() async { _ = await r.run(\"x\") } }", 0),
    ("final class R { func run(_ a: String) -> Int { DispatchQueue.global().async { p.waitUntilExit() }; return 0 } }\n"
     "@MainActor final class A { func f() { _ = r.run(\"x\") } }", 0),
    ("final class R { func ask(_ id: String) -> Bool { AEDeterminePermissionToAutomateTarget(d, 0, 0, false) == 0 } }\n"
     "struct V: View { var body: some View { if R().ask(\"x\") { Text(\"\") } } }", 1),
    ("@MainActor final class A { func f() { p.terminationHandler = { _ in p.waitUntilExit() } } }", 0),
    ("@MainActor final class A {}\nextension A { func g() { Thread.sleep(forTimeInterval: 0.1) } }", 1),
    ("@MainActor final class A { func f() { MacroStep.wait(ms: 5); x.wait(ms: 5) } }", 0),
    ("actor B { func f() { Thread.sleep(forTimeInterval: 1) } }", 0),
    ("@MainActor final class A { let restartQueue: (@escaping () -> Void) -> Void\n"
     "  func f() { restartQueue { p.waitUntilExit() } } }", 0),
    ("protocol P { func go() }\nfinal class L: P { func go() { p.waitUntilExit() } }\n"
     "@MainActor final class A { let p: P = L(); func f() { p.go() } }", 1),
]


def self_test():
    import tempfile
    failures = 0
    for i, (src, expected) in enumerate(SELF_TESTS):
        with tempfile.TemporaryDirectory() as root:
            d = os.path.join(root, "Apps/Mac/Sources")
            os.makedirs(d)
            with open(os.path.join(d, "T.swift"), "w") as fh:
                fh.write(src)
            got = len(check(root))
            if got != expected:
                failures += 1
                print(f"self-test {i}: expected {expected}, found {got}: {src!r}")
    print("self-test: " + ("passed" if not failures else f"{failures} failed"))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
