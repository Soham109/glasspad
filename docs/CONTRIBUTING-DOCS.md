# Documentation standard

How Glasspad's docs are organized and written. The goal: anyone finds the answer in seconds and can trust it matches the code.

## The rules

1. **Docs change in the same pull request as the code.** A change to an interface, a script, a command or a behavior updates its doc, or the pull request is not done.
2. **Lead with the answer.** First line says what the page or section is for.
3. **Skimmable.** Short sections, tables, lists and diagrams over paragraphs. A paragraph has three sentences at most.
4. **True.** Every name, path and command matches the code. Run each command you document before you commit.
5. **One home per fact.** Write it once and link to it. Do not copy a table between pages.

## Where each kind of doc lives

| Kind | Where | Example |
| --- | --- | --- |
| Project front page | `README.md` | What Glasspad is, install, features |
| How the code fits together | `ARCHITECTURE.md` | Diagrams, packages, threading |
| How to contribute | `CONTRIBUTING.md` | Branches, commits, definition of done |
| Security policy | `SECURITY.md` | Threat model, reporting |
| User-visible changes | `CHANGELOG.md` | One line per change under `Unreleased` |
| Developer guides | `docs/*.md` | [development](development.md), [testing](testing.md), [releasing](releasing.md) |
| Interface contracts | `docs/SPEC*.md` | Wire messages, macro model |
| Decisions and why | `docs/adr/NNNN-*.md` | [ADRs](adr/README.md) |
| Words and terms | `docs/glossary.md` | Add a term the first time a doc needs it |
| Old docs kept for history | `docs/archive/` | Not maintained; say so at the top |
| Images | `docs/img/` (screens), `docs/brand/` (icon) | Real screenshots only |
| Help for people using the app | The website, `web/site/pages.ts` | The guide and install pages |

Every new page in `docs/` gets a row in [docs/README.md](README.md).

## Style

| Do | Don't |
| --- | --- |
| Plain words, US spelling (color, behavior) | Jargon without a definition |
| Define a technical term in the same sentence, or link the [glossary](glossary.md) | Assume the reader knows macOS internals |
| Commas, colons, parentheses | Em dashes or en dashes |
| Facts from the code: names, values, paths | Estimates of time, invented numbers |
| `code font` for code names, files and commands | Bold for emphasis everywhere |
| Names macOS uses: Do Not Disturb, Mission Control, Split Screen | Made-up names for system features |
| Real screenshots from the app | Mockups presented as the app |
| Relative links inside the repo | Links to a branch other than `main` |

### Diagrams

Use [Mermaid](https://mermaid.js.org) in a fenced `mermaid` block. GitHub draws it. Keep each diagram to one idea and about ten boxes.

### Commands

- Show the command in a `bash` block, one command per line, with a short comment if it is not obvious.
- Run it from the repo root before you commit the doc.
- Say what it needs (Xcode, a simulator, a real iPhone) in a table or the line above.

## Templates

### Feature or guide page

~~~markdown
# Title: what this page helps you do

One sentence: who this is for and what they get.

| You want to | Go to |
| --- | --- |
| ... | [section](#section) |

## How it works

A Mermaid diagram if it has more than two moving parts.

| Piece | What it does | Code |
| --- | --- | --- |
| ... | ... | `Path/To/File.swift` |

## How to use or change it

```bash
the command
```

## Limits

- What it does not do, and why.

## Related

- [Other page](other.md)
~~~

### Architecture decision record

Copy [adr/template.md](adr/template.md). Sections: Context, Decision, Consequences (a Good and Cost table), Alternatives considered. One screen long. Add it to [adr/README.md](adr/README.md).

## Before you open the pull request

- [ ] Every command in your change ran.
- [ ] Every link resolves (relative links and anchors).
- [ ] Names and paths match the code (`grep` for them).
- [ ] No em dashes or en dashes: `python3 -c "import glob; [print(f) for f in glob.glob('*.md') + glob.glob('docs/**/*.md', recursive=True) if any(c in open(f).read() for c in '\u2013\u2014')]"` prints nothing.
- [ ] New page listed in [docs/README.md](README.md).
