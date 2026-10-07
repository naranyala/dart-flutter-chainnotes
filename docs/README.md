# Documentation

The working documentation for this project. The root
[`README.md`](../README.md) is the short entry point — what this is, how to run
it, and where every source file lives. These pages go deeper.

If you only read one of these, read
[the intent pyramid](../PYRAMID-OF-INTENTS.md). It states what the project is
for, the constraints that follow from that, and — importantly — a **current
state snapshot** that was checked against the tree and a full test run rather
than written from memory.

## Guides

| Guide | Read it when you want to know |
| --- | --- |
| [Overview](overview.md) | Why the project exists, what it does, and what it deliberately does not do |
| [Architecture](architecture.md) | Which layer owns which responsibility, and what happens between launch and first paint |
| [Tools](tools.md) | The six tools, the session behind each one, and how they reference each other's state |
| [Bridge protocol](bridge-protocol.md) | The request/response contract that survived the port, and what replaced the WebView bindings |
| [Development](development.md) | What to install, what to run, where the output lands, and what to do when it breaks |
| [Testing](testing.md) | Every test layer, what each suite actually proves, and how to run one |
| [Map sources](map-sources.md) | Tile hosts, the user agent, caching, attribution, and the licensing position |

## Planning

| Document | What it is |
| --- | --- |
| [Intent pyramid](../PYRAMID-OF-INTENTS.md) | The constraints a change must respect, and the verified current state |
| [TODOs](../TODOS.md) | The backlog. Every item carries an `Intent:` reference and a definition of done |

## How these documents are kept honest

Documentation drifts because nothing fails when it becomes wrong. One test
exists purely to turn silent mismatches into red ones:

| Test | What it catches |
| --- | --- |
| `test/readme_test.dart` | A source file missing from the README's repository map, a map entry pointing at a deleted file, a guide missing from this index, and a command in the README that is not one the project actually documents |

The rest of the guard is procedural and stated in
[the testing guide](testing.md#keeping-documents-honest): the bridge vocabulary,
the tool list, and the storage paths each have a test beside the code that
defines them, so the document quoting them is quoting something executable.

## The rule

**When behaviour changes, update the guide and the test in the same change.**
The repository map, the bridge vocabulary, and the supported commands are the
three places where a stale document sends someone confidently in the wrong
direction; those are especially worth the extra minute.
