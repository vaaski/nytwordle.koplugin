# NYTWordle

A Wordle plugin for [KOReader](https://github.com/koreader/koreader), forked as NYTWordle.

Install it in `plugins/nytwordle.koplugin/`. Its plugin ID is `nytwordle`, so its
menu entry, settings, and session statistics are separate from the original
`wordle` plugin. Both plugins can be installed together.


## Screenshot

![Screenshot](images/wordle.png)

## Rules

Guess the secret 5-letter word in 6 attempts. After each guess, tiles reveal: **green** = right letter right spot; **yellow** = right letter wrong spot; **grey** = letter not in word. The keyboard tracks used letters.

## Concept

Guess the hidden 5-letter word in 6 attempts. After each guess, each letter is marked:
- **Correct** — right letter, right position
- **Present** — letter is in the word but in the wrong position
- **Absent** — letter is not in the word

## Features

- **Two languages** — EN and FR
- **Separate answer and guess lists (EN)** — 2,307 common words can be the answer, while 8,637 are accepted as guesses, so ordinary English words are never rejected as "not a word"
- **On-screen keyboard** — shows letter status at a glance
- **Hard mode** — revealed hints must be used in subsequent guesses
- **NYT daily puzzle (EN)** — fetches the official answer for the device's local date from the NYT Wordle API
- **Past puzzles (EN)** — enter a date to play another day's NYT Wordle; progress is saved separately for each date
- **Offline free play** — unlimited random puzzles from the bundled word lists, also used when NYT requests fail
- **Statistics** — win streak, guess distribution histogram
- **Auto-save** — English opens today's puzzle and resumes its saved progress; French resumes the current random game

## Controls

| Action | How |
|--------|-----|
| Type a letter | Tap the on-screen keyboard |
| Delete last letter | Tap **⌫** |
| Submit guess | Tap **Enter** |
| Today's NYT puzzle (EN) | Tap **Today's Wordle (YYYY-MM-DD)** |
| Another NYT puzzle (EN) | Tap **Play another day's Wordle**, enter **YYYY-MM-DD**, then tap **Play** |
| New random game | Tap **Offline random word** in English or **New game** in French |
| Show rules | Tap **Rules** |

The date shown in the English menu comes from the device's local clock. Correct
the device date if it is wrong. Future dates and invalid calendar dates are
rejected. Previously loaded NYT puzzles can be resumed without a network request,
including completed games; selecting a date does not restart it or count its
result again. Wins, losses, and streak are shared across games.

Uncached puzzles require Internet access. Requests run in a dismissible background
process with network timeouts. If NYT does not respond, returns an error, or sends
an invalid puzzle, a message explains the failure and a new **Offline random word**
game starts. Offline games are not saved as official dated puzzles. Opening the
plugin again in English still attempts today's NYT puzzle. French remains random
play and does not use the NYT API.
Cancelling a download leaves the current game open.

## Why e-ink friendly?

Each guess is a discrete, low-frequency interaction. The letter-status feedback
uses distinct fill patterns (solid / hatched / empty) instead of colours alone,
so the puzzle remains readable on greyscale e-ink screens.

## License

GPL-3.0
