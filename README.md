# NYTWordle

A Wordle plugin for [KOReader](https://github.com/koreader/koreader), forked as NYTWordle.

Install it in `plugins/nytwordle.koplugin/`. Its plugin ID is `nytwordle`, so its
menu entry, settings, and session statistics are separate from the original
`wordle` plugin. Both plugins can be installed together.


## Screenshot

![Screenshot](images/wordle.png)

## Rules

Guess the secret 5-letter word in 6 attempts. After each guess, tiles reveal:
**dark** = right letter and position; **medium grey** = right letter, wrong
position; **light grey** = letter not in the word. The keyboard tracks used letters.

## Concept

Guess the hidden 5-letter word in 6 attempts. After each guess, each letter is marked:
- **Correct** — right letter, right position
- **Present** — letter is in the word but in the wrong position
- **Absent** — letter is not in the word

## Features

- **Two game modes** — NYT (English) and SPIEGEL (German), selected in the game-mode menu
- **Daily puzzles** — official NYT and SPIEGEL answers retrieved from their APIs
- **Past puzzles** — enter a date; each provider's progress is saved independently,
  including when both puzzles have the same date
- **Offline free play** — unlimited random puzzles from bundled answer pools;
  explicit offline selection resumes the current game on reopening
- **German dictionary** — 1,470 common offline answers and 7,854 additional accepted
  guesses, with umlauts and `ß` preserved as individual letters
- **On-screen keyboard** — English QWERTY or German QWERTZ with `Ä`, `Ö`, `Ü`, and
  lowercase `ß`, showing letter feedback
- **Statistics** — wins, losses, and streak shared across both providers and offline play
- **Auto-save** — unfinished rows and completed puzzles persist; online play opens
  today's puzzle on reopening without resetting saved progress

## Controls

| Action | How |
|--------|-----|
| Type a letter | Tap the on-screen keyboard |
| Delete last letter | Tap **⌫** |
| Submit guess | Tap **Enter** |
| Choose provider | Tap **Game mode: NYT/SPIEGEL**, then select a mode |
| Today's puzzle | Tap **Today's Wordle (YYYY-MM-DD)** |
| Another day's puzzle | Tap **Play another day's Wordle**, enter **YYYY-MM-DD**, then tap **Play** |
| New random game | Tap **Offline random word** |
| Show rules | Tap **Rules** |

NYT uses the device's local calendar date. SPIEGEL fetches its current puzzle
without specifying a date, using the server's puzzle date. If the server cannot
be reached, it uses Germany's date calculated from the device clock (CET/CEST,
including daylight-saving changes). Correct the device clock if it is wrong.
The SPIEGEL archive starts on **2024-12-14**. Date input uses **YYYY-MM-DD** in
both modes; the SPIEGEL adapter converts this to the API's **YYYYMMDD** path.
Invalid calendar dates and future dates are rejected.

Selecting a previously loaded date resumes it without downloading, including
completed games. Selecting a date never restarts it or counts its result again.
Opening SPIEGEL's daily puzzle checks the current endpoint first; if it is
unavailable, today's cached German puzzle can still be resumed.

Uncached puzzles require Internet access. Requests run in a dismissible background
process with network timeouts. If a provider does not respond, returns an error, or sends
an invalid puzzle, a message explains the failure and a new **Offline random word**
game starts. Offline games are not saved as official dated puzzles. Opening the
plugin again after a download failure still attempts today's puzzle. Choosing
**Offline random word** explicitly instead keeps the game offline on reopening.
Cancelling a download leaves the current game and provider selection intact.

## German word lists

`words_de.lua` contains a common-word subset of
[caco3/wordle-de's answer list](https://github.com/caco3/wordle-de/blob/main/target-words.json),
with its MIT notice in `licenses/wordle-de.txt`.

`spiegel_wordlist.txt` is the supplied German dictionary, very much like the
words accepted by spiegel.de. `guesses_de.lua` lazily transforms its concatenated
five-Unicode-character entries, converts letters to uppercase except `ß`, removes
duplicates and answer-pool entries, and excludes words containing characters
outside `A–Z`, `ÄÖÜ`, and `ß`. The source text must be included when installing the
plugin. All answer-pool words and downloaded answers are also accepted guesses.

## Why e-ink friendly?

Each guess is a discrete, low-frequency interaction. The letter-status feedback
uses distinct grayscale fills instead of colours,
so the puzzle remains readable on greyscale e-ink screens.

## License

GPL-3.0
