# Documentation

This is where the details live. The root [`README.md`](../README.md) is the
short version — what Chainnotes is, how to run it, and where everything is.
The pages below go one level deeper.

If you only have time for one page, make it
[the intent pyramid](../PYRAMID-OF-INTENTS.md). It explains what the project
is trying to do, the rules that follow from that, and what actually works
right now. That last part was checked against the code and a full test run,
not written from memory.

## Guides

| Guide | What you'll find there |
| --- | --- |
| [Overview](overview.md) | What the project is, how it feels to use, and what it doesn't try to be |
| [Architecture](architecture.md) | How the layers fit together, and what happens from launch to first paint |
| [Tools](tools.md) | The six tools, what each one remembers, and how they link to each other |
| [Bridge protocol](bridge-protocol.md) | The metrics request/response format, and the Dart APIs behind each tool |
| [Development](development.md) | What to install, which commands to run, where builds land, and fixes for common problems |
| [Testing](testing.md) | The test suites, what each one covers, and how to run them |
| [Map sources](map-sources.md) | Where map tiles come from, how they're cached, and attribution |

## Planning

| Document | What it is |
| --- | --- |
| [Intent pyramid](../PYRAMID-OF-INTENTS.md) | The rules a change should respect, plus an honest snapshot of the current state |
| [TODOs](../TODOS.md) | What's left to do. Every item points at an intent and says what "done" means |

## How we keep these pages honest

Docs go stale because nothing breaks when they do. We have one test that
turns a stale doc into a failing test:

| Test | What it catches |
| --- | --- |
| `test/readme_test.dart` | A source file missing from the README map, a map entry for a deleted file, a guide missing from this index, or a README command that isn't documented |

The rest is covered next to the code itself, as described in
[the testing guide](testing.md#keeping-documents-honest): the bridge codes,
the tool list, and the storage paths each have tests beside the code that
defines them, so the docs quote something the tests also check.

## The rule

**When behaviour changes, update the guide and the test together.**
The repository map, the bridge codes, and the supported commands are the
three places where an old doc sends someone confidently the wrong way, so
those are worth the extra minute.
