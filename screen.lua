local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Blitbuffer      = require("ffi/blitbuffer")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InfoMessage     = require("ui/widget/infomessage")
local InputDialog     = require("ui/widget/inputdialog")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local ScreenBase        = require("screen_base")
local MenuHelper        = require("menu_helper")
local KeyboardWidget    = lrequire("keyboard_widget")
local WordleBoard       = lrequire("board")
local WordleBoardWidget = lrequire("board_widget")
local NYT               = lrequire("nyt")
local Spiegel           = lrequire("spiegel")
local Dates             = lrequire("dates")
local PROVIDERS         = { nyt = NYT, spiegel = Spiegel }

local DeviceScreen = Device.screen

-- ---------------------------------------------------------------------------
-- WordleScreen
-- ---------------------------------------------------------------------------

local GAME_RULES_EN = _([[
NYTWordle — Rules

Guess the secret 5-letter word in 6 attempts.

After each guess:
• Dark tile — the letter is in the correct position.
• Medium grey tile — the letter is in the word but in the wrong position.
• Light grey tile — the letter is not in the word.

Use the on-screen keyboard to enter letters. Press ↵ to submit a guess, ⌫ to delete.
The keyboard shows the status of each letter used so far.

Choose NYT for English puzzles or SPIEGEL for German puzzles. Each mode
offers today's puzzle, past puzzles, and offline random words.
In German, Ä, Ö, Ü and ß each count as one distinct letter.
]])

local GAME_RULES_DE = [[
NYTWordle — Regeln

Errate das geheime Wort mit 5 Buchstaben in 6 Versuchen.

Nach jedem Versuch:
• Dunkles Feld — der Buchstabe steht an der richtigen Stelle.
• Mittleres Grau — der Buchstabe ist im Wort, aber an der falschen Stelle.
• Helles Grau — der Buchstabe ist nicht im Wort.

Gib Buchstaben über die Bildschirmtastatur ein. ↵ bestätigt, ⌫ löscht.
Die Tastatur zeigt die bisher bekannten Buchstaben an.
Ä, Ö, Ü und ß zählen jeweils als ein eigener Buchstabe.

NYT bietet englische Rätsel, SPIEGEL deutsche. Beide Modi unterstützen
das heutige Rätsel, das Archiv und Offline-Zufallswörter.
]]

local WordleScreen = ScreenBase:extend{}

function WordleScreen:init()
    local state = self.plugin:loadState()
    self.mode = self.plugin:getSetting("mode", "nyt")
    if not PROVIDERS[self.mode] then self.mode = "nyt" end
    local provider = PROVIDERS[self.mode]
    self.board = WordleBoard:new{ lang = provider.lang }
    self.board:load(state)
    if self.board.lang ~= provider.lang then self.board:randomGame(provider.lang) end
    ScreenBase.init(self)
    if not self.plugin:getSetting("offline", false) then
        local mode = self.mode
        UIManager:nextTick(function()
            if not self.closed and self.mode == mode and not self.plugin:getSetting("offline", false) then
                self:onToday()
            end
        end)
    end
end

function WordleScreen:serializeState()
    return self.board:serialize()
end

function WordleScreen:closeScreen()
    self.closed = true
    -- A cancelled/unfinished provider switch still belongs to the visible board.
    self.mode = self.board.lang == "de" and "spiegel" or "nyt"
    self.plugin:saveSetting("mode", self.mode)
    ScreenBase.closeScreen(self)
end

function WordleScreen:buildLayout()
    local sw           = DeviceScreen:getWidth()
    local sh = DeviceScreen:getHeight()
    local is_landscape = self:isLandscape()

    local btn_width = is_landscape
        and math.max(math.floor(sw * 0.38), 120)
        or  math.floor(sw * 0.9)

    self.status_text:setMaxWidth(btn_width)

    -- Top bar
    local title_bar = self:buildTitleBar(_("NYTWordle"), function()
        local items = {}
        items[#items + 1] = {
            text = T(_("Today's Wordle (%1)"), self:today()),
            callback = function() self:onToday() end,
        }
        items[#items + 1] = {
            text = _("Play another day's Wordle"),
            callback = function() self:openDateInput() end,
        }
        items[#items + 1] = {
            text = _("Offline random word"), callback = function() self:onNewGame(true) end,
        }
        items[#items + 1] = {
            text = T(_("Game mode: %1"), PROVIDERS[self.mode].name),
            callback = function() self:openModeMenu() end,
        }
        items[#items + 1] = {
            text = _("Rules"),
            callback = function() self:showRules(_.lang() == "de" and GAME_RULES_DE or GAME_RULES_EN) end,
        }
        return items
    end)

    -- Board widget
    local max_cell = is_landscape and math.floor(sh * 0.7) or math.floor(sw * 0.9)
    local max_w    = math.floor(max_cell * (self.board.word_len / self.board.max_tries))
    local max_h    = max_cell
    if is_landscape then
        max_w = math.floor(sw * 0.42)
        max_h = sh - 40
    end

    self.board_widget = WordleBoardWidget:new{
        board      = self.board,
        max_width  = math.max(max_w, 60),
        max_height = math.max(max_h, 60),
    }

    local board_frame = FrameContainer:new{
        padding = Size.padding.default,
        margin  = Size.margin.default,
        self.board_widget,
    }

    self.keyboard_widget = KeyboardWidget.build{
        width     = btn_width,
        layout    = self.board.lang == "de" and "qwertz" or "qwerty",
        backspace = true,
        enter     = true,
        onKey     = function(k) self:onVirtualKey(k) end,
        keyColor  = function(k)
            local ks = self.board.key_state[k]
            if ks == WordleBoard.STATE_CORRECT then return Blitbuffer.COLOR_GRAY_4 end
            if ks == WordleBoard.STATE_PRESENT then return Blitbuffer.COLOR_GRAY_9 end
            if ks == WordleBoard.STATE_ABSENT  then return Blitbuffer.COLOR_GRAY_D end
            return nil
        end,
    }

    if is_landscape then
        local right = VerticalGroup:new{
            align = "center",
            self.status_text,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.keyboard_widget,
        }
        local content = HorizontalGroup:new{
            align  = "center",
            board_frame,
            HorizontalSpan:new{ width = Size.span.horizontal_default },
            right,
        }
        self:buildLandscapeLayout(title_bar, content)
    else
        local footer = VerticalGroup:new{
            align = "center",
            self.keyboard_widget,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
        }
        self:buildPortraitLayout(title_bar, board_frame, footer)
    end
    self:updateStatus()
end

function WordleScreen:onVirtualKey(key)
    if self.fetching then return end
    if key == "↵" then
        local result = self.board:submit()
        if result == "short" then
            self:updateStatus(_("Word too short!"))
            return
        elseif result == "invalid" then
            self:updateStatus(_("Not in word list!"))
            return
        end
        -- Rebuild layout so keyboard reflects updated key_state colours.
        self:saveAndRefresh()
    elseif key == "⌫" then
        self.board:deleteLetter()
        self.board_widget:refresh()
        self:updateStatus()
    else
        self.board:typeLetter(key)
        self.board_widget:refresh()
        self:updateStatus()
    end
end

function WordleScreen:onNewGame(explicit)
    if self.fetching then return end
    self.plugin:saveSetting("offline", explicit == true)
    self.board:randomGame(PROVIDERS[self.mode].lang)
    self:saveAndRefresh()
end

function WordleScreen:saveAndRefresh()
    self.plugin:saveSetting("mode", self.mode)
    self.plugin:saveState(self:serializeState())
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

-- - daily puzzles ------------------------------------------------------------

function WordleScreen:today()
    if self.mode == "spiegel" and self.spiegel_today then
        -- Advance the authoritative server date as the device clock advances.
        return Dates.advance(self.spiegel_today, self.spiegel_device_date, Spiegel.today())
    end
    return PROVIDERS[self.mode].today()
end

function WordleScreen:onToday(on_cancel)
    if self.mode == "spiegel" then
        self:playDate(nil, on_cancel)
    else
        self:playDate(self:today(), on_cancel)
    end
end

function WordleScreen:playDate(date, on_cancel)
    if self.closed or self.fetching then return end
    local provider = PROVIDERS[self.mode]
    if date and not provider.isValidDate(date, self:today()) then
        UIManager:show(InfoMessage:new{ text = _("Enter a valid date in YYYY-MM-DD format, no later than today.") })
        return
    end
    if date and self.board:selectDate(date, nil, provider.lang) then
        self.plugin:saveSetting("offline", false)
        self:saveAndRefresh()
        return
    end

    self.fetching = true
    local Trapper = require("ui/trapper")
    Trapper:wrap(function()
        local completed, solution, err, puzzle_date = Trapper:dismissableRunInSubprocess(function()
            return provider.fetch(date)
        end, T(_("Loading %1 Wordle…"), provider.name))
        self.fetching = false
        if self.closed then return end
        if not completed then
            if on_cancel then on_cancel() end
            return
        end
        if solution then
            if not date and provider == Spiegel then
                self.spiegel_today = puzzle_date
                self.spiegel_device_date = Spiegel.today()
            end
            self.board:selectDate(puzzle_date or date, solution, provider.lang)
            self.plugin:saveSetting("offline", false)
            self:saveAndRefresh()
        else
            -- An unavailable server must not hide a previously downloaded daily game.
            if not date and self.board:selectDate(self:today(), nil, provider.lang) then
                self.plugin:saveSetting("offline", false)
                self:saveAndRefresh()
                return
            end
            self:onNewGame()
            UIManager:show(InfoMessage:new{
                text = T(_("Could not load %1 Wordle (%2). Playing an offline random word instead."),
                    provider.name, err or _("No response")),
            })
        end
    end)
end

function WordleScreen:openDateInput()
    local dialog
    dialog = InputDialog:new{
        title = _("Play another day's Wordle"),
        input = self.board.puzzle_date or self:today(),
        input_type = "string",
        description = T(_("YYYY-MM-DD — %1 date: %2"), PROVIDERS[self.mode].name, self:today())
            .. "\n" .. T(_("Archive starts on %1."), PROVIDERS[self.mode].first_date),
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Play"), is_enter_default = true, callback = function()
                local date = dialog:getInputValue()
                if not PROVIDERS[self.mode].isValidDate(date, self:today()) then
                    UIManager:show(InfoMessage:new{
                        text = _("Enter a valid date in YYYY-MM-DD format, no later than today."),
                    })
                    return
                end
                UIManager:close(dialog)
                self:playDate(date)
            end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function WordleScreen:openModeMenu()
    if self.fetching then return end
    local items = {
        { id = "nyt", text = _("NYT (English)") },
        { id = "spiegel", text = _("SPIEGEL (German)") },
    }
    MenuHelper.openPickerMenu{
        title      = _("Game mode"),
        items      = items,
        current_id = self.mode,
        parent     = self,
        on_select  = function(mode)
            if self.fetching or self.closed or mode == self.mode then return end
            local previous_mode = self.mode
            self.mode = mode
            self:onToday(function()
                self.mode = previous_mode
                self:saveAndRefresh()
            end)
        end,
    }
end

function WordleScreen:updateStatus(msg)
    local status
    if msg then
        status = msg
    elseif self.board.won then
        local attempt = #self.board.guesses
        status = T(_("Solved in %1! Streak: %2"), attempt, self.board.streak)
    elseif self.board.lost then
        status = T(_("Lost! Word: %1  W:%2 L:%3"),
            self.board.secret, self.board.wins, self.board.losses)
    else
        local typed = table.concat(self.board.current)
        if typed ~= "" then
            status = T(_("Try %1/%2: %3"), self.board.row, self.board.max_tries, typed)
        else
            status = T(_("Try %1/%2  W:%3 L:%4"),
                self.board.row, self.board.max_tries,
                self.board.wins, self.board.losses)
        end
    end
    if self.board.puzzle_date then
        status = self.board.puzzle_date .. " — " .. status
    else
        status = _("Offline random word") .. " — " .. status
    end
    local name = self.board.lang == "de" and Spiegel.name or NYT.name
    status = name .. " — " .. status
    ScreenBase.updateStatus(self, status)
end

return WordleScreen
