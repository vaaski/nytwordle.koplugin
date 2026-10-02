local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local Board = assert(loadfile(DIR .. "board.lua"))()
local Letters = assert(loadfile(DIR .. "letters.lua"))()
local Dates = assert(loadfile(DIR .. "dates.lua"))()

local function guess(board, word)
    board.current = {}
    for _, letter in ipairs(Letters.split(word)) do board:typeLetter(letter) end
    return board:submit()
end

describe("German games", function()
    it("keeps the two dictionaries disjoint, playable and large enough for free play", function()
        local answers = assert(loadfile(DIR .. "words_de.lua"))()
        local guesses = assert(loadfile(DIR .. "guesses_de.lua"))()
        local seen = {}
        for _, list in ipairs({ answers, guesses }) do
            for _, word in ipairs(list) do
                assert.is_true(Letters.isWord(word, "de"), word)
                assert.is_nil(seen[word], word)
                seen[word] = true
            end
        end
        assert.is_true(#answers > 1000)
        assert.is_true(#guesses > 7000)
        assert.is_true(seen["ABMAß"])
        assert.is_nil(seen["APRÈS"])
        local answer_set = {}
        for _, word in ipairs(answers) do answer_set[word] = true end
        for _ = 1, 100 do assert.is_true(answer_set[Board:new{ lang = "de" }.secret]) end
    end)

    it("treats umlauts and lowercase sharp S as individual letters", function()
        local board = Board:new{ lang = "de" }
        board:newGame("GRÜßE")
        assert.are.equal("win", guess(board, "grüße"))
        assert.are.same({ "G", "R", "Ü", "ß", "E" }, board.guesses[1].letters)
        assert.are.equal(Board.STATE_CORRECT, board.key_state["ß"])
        board:newGame("GRÜßE")
        board:typeLetter("ẞ")
        assert.are.same({ "ß" }, board.current)
        board:deleteLetter()
        assert.are.same({}, board.current)
    end)

    it("scores duplicate umlauts without awarding more matches than the answer contains", function()
        local board = Board:new{ lang = "de" }
        board:newGame("ÄPFEL")
        local C, P, A = Board.STATE_CORRECT, Board.STATE_PRESENT, Board.STATE_ABSENT
        assert.are.same({ P, P, C, C, A }, board:_evaluate("LÄFEÄ"))
        assert.are.same({ C, A, A, A, A }, board:_evaluate("ÄÄÄÄÄ"))
    end)

    it("preserves keyboard feedback and terminal losses in German", function()
        local board = Board:new{ lang = "de" }
        board:newGame("GRÜNE")
        assert.are.equal("ok", guess(board, "WÜRDE"))
        assert.are.equal(Board.STATE_PRESENT, board.key_state["Ü"])
        assert.are.equal("ok", guess(board, "MÜTZE"))
        assert.are.equal(Board.STATE_PRESENT, board.key_state["Ü"])
        for _ = 1, 4 do guess(board, "APFEL") end
        assert.is_true(board.lost)
        assert.are.equal(1, board.losses)
        assert.are.equal("done", guess(board, "GRÜNE"))
    end)

    it("isolates providers on the same date and shares counters across them", function()
        local board = Board:new()
        board:selectDate("2026-10-02", "APPLE", "en")
        assert.are.equal("win", guess(board, "APPLE"))
        board:selectDate("2026-10-02", "GRÜßE", "de")
        board:typeLetter("ü")
        local reopened = Board:new()
        assert.is_true(reopened:load(board:serialize()))
        assert.is_true(reopened:selectDate("2026-10-02", nil, "en"))
        assert.is_true(reopened.won)
        assert.are.equal(1, reopened.wins)
        assert.is_true(reopened:selectDate("2026-10-02", nil, "de"))
        assert.are.same({ "Ü" }, reopened.current)
        assert.are.equal("win", guess(reopened, "GRÜßE"))
        assert.are.equal(2, reopened.wins)
        assert.are.equal(2, reopened.streak)
        reopened:selectDate("2026-10-02", nil, "en")
        assert.are.equal("done", guess(reopened, "APPLE"))
        assert.are.equal(2, reopened.wins)
    end)

    it("loads previously saved bare-date English history", function()
        local board = Board:new()
        assert.is_true(board:load({ lang = "en", secret = "ABOUT", dated_games = {
            ["2026-10-01"] = { lang = "en", secret = "APPLE", current = { "P" } },
        } }))
        assert.is_true(board:selectDate("2026-10-01", nil, "en"))
        assert.are.same({ "P" }, board.current)
        assert.is_false(board:selectDate("2026-10-01", nil, "de"))
    end)

    it("ignores removed-language saves and rejects characters that have no key", function()
        local board = Board:new()
        assert.is_false(board:load({ lang = "fr", secret = "ARBRE" }))
        board:typeLetter("Ü")
        board:typeLetter("AA")
        assert.are.same({}, board.current)
    end)
end)

describe("Germany's calendar date", function()
    it("uses CET in winter and CEST in summer, regardless of device timezone", function()
        assert.are.equal("2026-01-02", Dates.germanyToday(1767308400)) -- Jan 1 23:00 UTC
        assert.are.equal("2026-07-02", Dates.germanyToday(1782943200)) -- Jul 1 22:00 UTC
    end)

    it("changes offsets at the last Sunday of March and October", function()
        -- At 22:30 UTC, the date differs depending on the DST offset.
        assert.are.equal("2026-03-28", Dates.germanyToday(1774737000))
        assert.are.equal("2026-03-30", Dates.germanyToday(1774823400))
        assert.are.equal("2026-10-25", Dates.germanyToday(1792881000))
        assert.are.equal("2026-10-25", Dates.germanyToday(1792967400))
    end)
end)
