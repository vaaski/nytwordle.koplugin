# Codebase guide

## Project and runtime

NYTWordle is a Lua Wordle plugin for KOReader with two provider modes: NYT
(English) and SPIEGEL (German). Each offers daily, archive, and offline random
play. Its plugin ID is `nytwordle`; install it in `plugins/nytwordle.koplugin/`.

KOReader supplies UI, device, settings, gettext, FFI, and networking modules.
The UI cannot run as a standalone Lua app. The board, letter helpers, date
helpers, and response decoding can run headlessly; network tests stub KOReader's
HTTP dependencies.

## Where to work

| Path | Responsibility |
| --- | --- |
| `main.lua`, `_meta.lua` | Plugin entry point, translation registration, display metadata, and release version. |
| `board.lua` | Word lists, input, validation, duplicate scoring, keyboard states, shared counters, and saved puzzle history. |
| `screen.lua` | Provider selection, daily/archive/offline workflows, persistence, portrait/landscape composition, status, and rules. |
| `board_widget.lua` | Six-row board drawing and repaint regions; feedback uses grayscale fills. |
| `keyboard_widget.lua` | Plugin-local QWERTY/QWERTZ keyboard, special keys, and per-letter shading. |
| `letters.lua` | UTF-8 letter splitting, case normalization, and playable English/German alphabet validation. |
| `dates.lua` | Calendar validation, device-local date, Germany's CET/CEST date, and advancing a server-established date. |
| `nyt.lua`, `spiegel.lua` | Provider metadata, date validation, API retrieval, and response validation. |
| `puzzle_http.lua` | Shared JSON HTTP retrieval with KOReader socket dependencies and timeout restoration. |
| `words_en.lua`, `words_de.lua` | Bundled offline answer pools. |
| `guesses_en.lua`, `guesses_de.lua` | Accepted guess lists; the German module transforms the source dictionary lazily. |
| `spiegel_wordlist.txt` | Required German dictionary source: concatenated five-Unicode-character words. Include it in deployment. |
| `translations.lua` | Plugin-specific German and Spanish UI translations; UI locale follows KOReader. |
| `common/` | Shared game library, symlinked during development and bundled for releases. |
| `test_*_spec.lua`, `.busted` | Root-level Busted tests and discovery configuration. |
| `README.md`, `images/` | User-facing behavior, controls, word-list attribution, and screenshot assets. |
| `CONTRIBUTING.md`, `CHANGELOG.md`, `LICENSE`, `licenses/` | Contribution/release guidance, history, plugin license, and third-party notices. |

## Runtime flow and boundaries

1. `main.lua` extends `common/plugin_base.lua`. The base registers the Tools
   menu entry and opens a single screen through `createScreen()`.
2. `WordleScreen:init()` reads `mode` (`nyt` by default, or `spiegel`), restores
   the board, aligns its internal `lang` (`en`/`de`) with the provider, and builds
   the screen. Unless the `offline` setting is true, a next-tick callback opens
   today's puzzle. Explicit offline play resumes the saved current game.
3. On-screen keys call `screen.lua:onVirtualKey()`, which delegates game rules
   to the board. Typing/deletion refresh the board widget; submissions rebuild
   the layout to update keyboard colors and save state.
4. Provider selection opens that provider's daily puzzle. A successful dated
   selection clears the offline preference. Explicit random play sets it;
   download-failure fallback clears it so reopening retries online. Switching
   providers retains shared counters and dated histories; cancelling a download
   retains the current board and restores a pending provider selection.
5. Normal screen close saves the full board, including the unfinished row,
   through `ScreenBase:closeScreen()`. `PluginBase:onScreenClosed()` records
   session duration and clears the active screen reference.

Keep game rules and saved data in `board.lua`, API-specific validation in the
provider modules, UI actions in `screen.lua`, and rendering in the widget modules.

### Online puzzles and dates

- NYT requests `https://www.nytimes.com/svc/wordle/v2/YYYY-MM-DD.json` using the
  device's local date. The response must match `print_date` and contain five
  ASCII letters.
- SPIEGEL requests
  `https://api.spiegel.raetselzentrale.com/api/v3/l/spiegel/wordlearchiv?channel=www.spiegel.de`
  for today, or inserts `/YYYYMMDD` before the query for archive puzzles.
  Its archive starts on `2024-12-14`. `ckey` establishes the puzzle date;
  decoding validates the complete 5×6 grid and agreement between answer rows.
- Date input is strict `YYYY-MM-DD` and rejects future dates. SPIEGEL's fetched
  date is authoritative within the screen session and advances with elapsed
  Germany-calendar days, preserving the server/device date offset. Without a
  fetched date, `dates.lua` calculates Germany's date from the device clock.
- Fetching runs through `Trapper:dismissableRunInSubprocess()`; providers return
  `solution, error, puzzle_date`. HTTP dependencies load only on retrieval;
  requests use 5-second block/15-second total timeouts and restore prior values.
- Explicit cached date selection avoids HTTP. SPIEGEL's daily action checks the
  current endpoint first and resumes today's cached German game on failure.
  Otherwise retrieval failure starts a labeled, undated random game.

### Module loading

`main.lua` prepends the plugin root and `common/` to `package.path`. Plugin-local
modules use `lrequire()`: `loadfile()` relative to the current source file,
cached in `package.loaded` under a directory-qualified key. Preserve this
pattern to avoid collisions with other plugins' generic `board`/`screen` names.
Shared base modules are generally loaded with `require()`; the grid drawing
helper uses `lrequire("common/grid_widget_base")`. The keyboard is plugin-local.
Word-list files are loaded lazily by `board.lua` and cached per language.

### Shared dependencies

- `common/plugin_base.lua`: menu registration, settings/state storage, screen
  lifecycle, plugin deletion hooks, and session statistics. Settings live in
  KOReader's settings directory as `<plugin_id>.lua`; use `getPluginId()` for
  stable identity because KOReader can rewrite `name`.
- `common/screen_base.lua`: full-screen painting, title/menu/close controls,
  portrait/landscape layout helpers, status updates, and rules dialogs.
- `common/menu_helper.lua`: provider-mode picker.
- `common/grid_widget_base.lua`: only its `drawLine` helper is used by the
  Wordle widget; the widget extends KOReader's `InputContainer` directly.
- `common/i18n.lua`: shared translations, plugin translation extension, and
  fallback to KOReader gettext. UI language follows KOReader's language setting;
  provider mode independently selects the puzzle dictionary and keyboard.
- `common/stats_exporter.lua`: shared session statistics, used by `PluginBase`.

For shared-library changes, read `common/README.md` and the relevant module.
In this checkout, `common` points to `../game-common`; a missing target prevents
UI module loading. Release packaging copies the shared library into `common/`.

## Model invariants and implementation caveats

- Default play is five letters and six attempts. Rows and letter positions are
  one-indexed. `newGame()` resets play state while retaining wins/losses/streak.
- All bundled and downloaded answers are valid guesses, even when an API answer
  is absent from the dictionary. Random games draw only from answer pools.
- Five letters means five Unicode characters, not five bytes. Use `letters.lua`
  for splitting and normalization. German supports `A–Z`, `ÄÖÜ`, and lowercase
  `ß`; lowercase umlauts normalize to uppercase, and `ẞ` normalizes to `ß`.
  Umlauts and sharp S each occupy one tile and remain distinct from ASCII.
- `guesses_de.lua` splits the supplied dictionary into five-character entries,
  removes duplicates and answer-pool entries, and excludes unsupported letters
  and punctuation. Preserve word-list attribution and `licenses/wordle-de.txt`
  when changing the offline German pool sourced from `caco3/wordle-de`.
- Evaluation matches exact positions first, then consumes remaining secret
  positions for misplaced letters. Preserve this two-pass duplicate handling.
- Keyboard feedback only improves: correct outranks present, which outranks
  absent. Use the exported `STATE_*` constants rather than duplicating numbers.
- `serialize()`/`load()` define the save format. Preserve compatibility with
  supported existing saves when changing model fields. `dated_games` is keyed
  by `en:YYYY-MM-DD` or `de:YYYY-MM-DD`; legacy bare-date English keys are loaded
  as `en:` keys. Top-level fields retain the active board and global counters.
- Restoring a dated snapshot preserves current global counters. Completed games
  remain completed and cannot award the same win/loss twice. Random play stores
  the outgoing dated game before clearing `puzzle_date`.
- Supported puzzle languages are only `en` and `de`; removed-language active
  saves are rejected without migration.
- Hard mode, a guess-distribution histogram, patterned fills, and local seeded
  daily puzzles are not implemented. Official daily answers come from APIs.

## Verification and releases

Run `busted` from the plugin root using `.busted`. Run a relevant file while
iterating, for example `busted test_german_spec.lua` or
`busted test_spiegel_spec.lua test_screen_spec.lua`. Tests cover the board,
dated persistence, both provider adapters, Germany's dates, German letters and
dictionaries, mocked screen workflows, and mocked keyboard layout wiring.
`common/test_hint_spec.lua` covers the shared hint helper; run it when changing
that helper.

Known baseline: the English dictionary-disjointness test fails because
`words_en.lua` and `guesses_en.lua` overlap (`AAHED` is the first reported word).
Distinguish that existing failure from regressions in changed behavior.

For model changes, exercise validation, repeated-letter scoring, terminal
win/loss behavior, and save/load headlessly. For UI changes, verify in KOReader:
portrait/landscape rendering, keyboard shading and German special keys,
provider switching, daily/archive/offline actions, cancellation and fallback,
and close/reopen persistence. Mocked UI tests do not verify device rendering.
Record which checks were actually run.

Follow existing Lua formatting: four-space indentation, local dependencies,
colon methods, and separator comments for logical sections. Releases are
maintainer-managed; change `_meta.lua`'s version only when requested.
