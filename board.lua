local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end
local Letters = lrequire("letters")

-- ---------------------------------------------------------------------------
-- Word lists
-- ---------------------------------------------------------------------------

-- Two files per language, the way Wordle itself splits them:
--   words_<lang>.lua    -- words common enough to be a fair answer
--   guesses_<lang>.lua  -- everything else the game still accepts as a guess
--
-- English used to be a single 716-word table inlined right here, serving as
-- the answer pool AND as the whole notion of "is that even a word", so
-- ordinary guesses (STARE, TEARS, IRATE, NOTES, FJORD, LYMPH...) came back
-- as "not a word". Both supported languages now have additional guess lists.
--
-- Loaded lazily: the English guess list alone is several thousand words, and
-- a player who never opens Wordle should not pay for it.

local _lists = {}

local function loadLang(lang)
    local entry = _lists[lang]
    if entry then return entry end

    entry = { answers = {}, valid = {} }
    local answers_fn = loadfile(_dir .. "words_" .. lang .. ".lua")
    entry.answers = (answers_fn and answers_fn()) or {}
    for _, w in ipairs(entry.answers) do entry.valid[w] = true end

    -- Every answer is also a valid guess, so guesses_<lang>.lua only needs to
    -- carry the extras -- no duplication between the two files.
    local guesses_fn = loadfile(_dir .. "guesses_" .. lang .. ".lua")
    if guesses_fn then
        for _, w in ipairs(guesses_fn() or {}) do entry.valid[w] = true end
    end

    _lists[lang] = entry
    return entry
end

-- Filter to exact word_len
local function filterWords(list, len)
    local out = {}
    for _, w in ipairs(list) do
        if #Letters.split(w) == len then out[#out + 1] = w end
    end
    return out
end

-- Candidate answers for lang (returns array)
local function getWordList(lang, len)
    return filterWords(loadLang(lang).answers, len)
end

-- Accepted as a guess: an answer, or one of the extra words for that language.
local function isValidWord(lang, word)
    return loadLang(lang).valid[word] == true
end

local WORD_LEN   = 5
local MAX_TRIES  = 6
local LANG_ORDER = { "en", "de" }

-- Cell result states
local STATE_EMPTY   = 0
local STATE_TBD     = 1   -- typed but not submitted
local STATE_CORRECT = 2   -- right letter, right position
local STATE_PRESENT = 3   -- right letter, wrong position
local STATE_ABSENT  = 4   -- letter not in word

-- ---------------------------------------------------------------------------
-- WordleBoard
-- ---------------------------------------------------------------------------

local WordleBoard = {}
WordleBoard.__index = WordleBoard

function WordleBoard:new(opts)
    opts = opts or {}
    local obj = setmetatable({
        lang      = opts.lang == "de" and "de" or "en",
        word_len  = opts.word_len or WORD_LEN,
        max_tries = MAX_TRIES,
        secret    = "",
        guesses   = {},   -- array of { letters={}, states={} }
        current   = {},   -- current row letters (array of chars)
        row       = 1,    -- current attempt (1-indexed)
        won       = false,
        lost      = false,
        -- keyboard state per letter
        key_state = {},
        wins      = 0,
        losses    = 0,
        streak    = 0,
        dated_games = {},
    }, self)
    obj:_newWord()
    return obj
end

function WordleBoard:_newWord()
    local list = getWordList(self.lang, self.word_len)
    if #list == 0 then list = filterWords(loadLang("en").answers, self.word_len) end
    -- Every bundled list is 5-letter only, so a word_len of anything else
    -- leaves both filters empty and math.random(0) would raise. Nothing sets
    -- word_len today, but a saved game from a future build might.
    if #list == 0 then list = loadLang("en").answers end
    if #list == 0 then return end
    self.secret = list[math.random(#list)]
end

function WordleBoard:newGame(secret, puzzle_date)
    if secret then
        assert(Letters.isWord(secret, self.lang), "Answer must be five playable letters")
        self.word_len = WORD_LEN
        self.secret = secret
    else
        self:_newWord()
    end
    self.puzzle_date = puzzle_date
    self.guesses  = {}
    self.current  = {}
    self.row      = 1
    self.won      = false
    self.lost     = false
    self.key_state = {}
end

-- Type a letter
function WordleBoard:typeLetter(letter)
    if self.won or self.lost then return end
    if #self.current >= self.word_len then return end
    if type(letter) ~= "string" then return end
    letter = Letters.upper(letter)
    if not Letters.isLetter(letter, self.lang) then return end
    self.current[#self.current + 1] = letter
end

-- Delete last letter
function WordleBoard:deleteLetter()
    if self.won or self.lost then return end
    if #self.current == 0 then return end
    table.remove(self.current)
end

-- Submit current guess. Returns "short", "invalid", "win", "lose", "ok"
function WordleBoard:submit()
    if self.won or self.lost then return "done" end
    if #self.current < self.word_len then return "short" end

    local guess_str = table.concat(self.current)
    if guess_str ~= self.secret and not isValidWord(self.lang, guess_str) then return "invalid" end
    local states    = self:_evaluate(guess_str)
    self.guesses[#self.guesses + 1] = {
        letters = { table.unpack(self.current) },
        states  = states,
    }

    -- Update keyboard states
    for i, letter in ipairs(self.current) do
        local st = states[i]
        local existing = self.key_state[letter]
        -- CORRECT > PRESENT > ABSENT > nil
        if not existing
                or (st == STATE_CORRECT)
                or (st == STATE_PRESENT and existing ~= STATE_CORRECT) then
            self.key_state[letter] = st
        end
    end

    self.current = {}
    self.row     = self.row + 1

    if guess_str == self.secret then
        self.won    = true
        self.wins   = self.wins + 1
        self.streak = self.streak + 1
        return "win"
    elseif self.row > self.max_tries then
        self.lost   = true
        self.losses = self.losses + 1
        self.streak = 0
        return "lose"
    end
    return "ok"
end

function WordleBoard:_evaluate(guess)
    local states  = {}
    local secret  = Letters.split(self.secret)
    guess = Letters.split(guess)
    local used    = {}  -- secret letter positions already matched

    -- First pass: correct positions
    for i = 1, self.word_len do
        if guess[i] == secret[i] then
            states[i] = STATE_CORRECT
            used[i]   = true
        else
            states[i] = STATE_ABSENT
        end
    end

    -- Second pass: present but wrong position
    for i = 1, self.word_len do
        if states[i] ~= STATE_CORRECT then
            local ch = guess[i]
            for j = 1, self.word_len do
                if not used[j] and secret[j] == ch then
                    states[i] = STATE_PRESENT
                    used[j]   = true
                    break
                end
            end
        end
    end

    return states
end

-- - dated puzzles ------------------------------------------------------------

function WordleBoard:rememberCurrent()
    if self.puzzle_date then
        self.dated_games[self.lang .. ":" .. self.puzzle_date] = self:_serializePuzzle()
    end
end

function WordleBoard:selectDate(date, solution, lang)
    lang = lang or "en"
    assert(lang == "en" or lang == "de", "Unsupported puzzle language")
    self:rememberCurrent()
    local saved = self.dated_games[lang .. ":" .. date]
    if saved then
        -- Date snapshots contain historical counters; retain the current totals.
        local wins, losses, streak = self.wins, self.losses, self.streak
        self:_loadPuzzle(saved)
        self.wins, self.losses, self.streak = wins, losses, streak
        return true
    end
    if not solution then return false end

    self.lang = lang
    self:newGame(solution, date)
    self:rememberCurrent()
    return true
end

function WordleBoard:randomGame(lang)
    assert(lang == "en" or lang == "de", "Unsupported puzzle language")
    self:rememberCurrent()
    self.lang = lang
    self:newGame()
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

function WordleBoard:serialize()
    self:rememberCurrent()
    -- Preserve the original top-level board fields for existing saves.
    local state = self:_serializePuzzle()
    state.dated_games = self.dated_games
    return state
end

function WordleBoard:_serializePuzzle()
    return {
        lang      = self.lang,
        word_len  = self.word_len,
        secret    = self.secret,
        puzzle_date = self.puzzle_date,
        guesses   = self.guesses,
        current   = self.current,
        row       = self.row,
        won       = self.won,
        lost      = self.lost,
        key_state = self.key_state,
        wins      = self.wins,
        losses    = self.losses,
        streak    = self.streak,
    }
end

function WordleBoard:load(data)
    if not self:_loadPuzzle(data) then return false end
    self.dated_games = {}
    for key, saved in pairs(type(data.dated_games) == "table" and data.dated_games or {}) do
        if type(key) == "string" and type(saved) == "table"
                and (saved.lang == nil or saved.lang == "en" or saved.lang == "de") then
            -- Existing English saves used bare dates; provider histories must not collide.
            local dated_key = key
            if key:match("^%d%d%d%d%-%d%d%-%d%d$") then dated_key = "en:" .. key end
            self.dated_games[dated_key] = saved
        end
    end
    return true
end

function WordleBoard:_loadPuzzle(data)
    if type(data) ~= "table" or not data.secret then return false end
    if data.lang and data.lang ~= "en" and data.lang ~= "de" then return false end
    self.lang      = data.lang      or "en"
    self.word_len  = data.word_len  or WORD_LEN
    self.secret    = data.secret    or ""
    self.puzzle_date = data.puzzle_date
    self.guesses   = data.guesses   or {}
    self.current   = data.current   or {}
    self.row       = data.row       or 1
    self.won       = data.won       or false
    self.lost      = data.lost      or false
    self.key_state = data.key_state or {}
    self.wins      = data.wins      or 0
    self.losses    = data.losses    or 0
    self.streak    = data.streak    or 0
    return true
end

WordleBoard.STATE_EMPTY   = STATE_EMPTY
WordleBoard.STATE_TBD     = STATE_TBD
WordleBoard.STATE_CORRECT = STATE_CORRECT
WordleBoard.STATE_PRESENT = STATE_PRESENT
WordleBoard.STATE_ABSENT  = STATE_ABSENT
WordleBoard.LANG_ORDER    = LANG_ORDER
WordleBoard.WORD_LEN      = WORD_LEN
WordleBoard.MAX_TRIES     = MAX_TRIES

return WordleBoard
