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
local KeyboardWidget    = lrequire("common/keyboard_widget")
local WordleBoard       = lrequire("board")
local WordleBoardWidget = lrequire("board_widget")
local NYT               = lrequire("nyt")

local DeviceScreen = Device.screen

-- ---------------------------------------------------------------------------
-- WordleScreen
-- ---------------------------------------------------------------------------

local GAME_RULES_EN = _([[
Wordle — Rules

Guess the secret 5-letter word in 6 attempts.

After each guess:
• Green tile — the letter is in the correct position.
• Yellow tile — the letter is in the word but in the wrong position.
• Grey tile — the letter is not in the word.

Use the on-screen keyboard to enter letters. Press ↵ to submit a guess, ⌫ to delete.
The keyboard shows the status of each letter used so far.
]])

local GAME_RULES_FR = [[
Wordle — Règles

Devinez le mot secret de 5 lettres en 6 tentatives.

Après chaque proposition :
• Case verte — la lettre est à la bonne position.
• Case jaune — la lettre est dans le mot mais à la mauvaise position.
• Case grise — la lettre n'est pas dans le mot.

Utilisez le clavier à l'écran pour entrer des lettres. Appuyez sur ↵ pour valider, sur ⌫ pour effacer.
Le clavier affiche l'état de chaque lettre utilisée.
]]

local WordleScreen = ScreenBase:extend{}

function WordleScreen:init()
    local state = self.plugin:loadState()
    local lang  = self.plugin:getSetting("lang", "en")
    self.board = WordleBoard:new{ lang = lang }
    self.board:load(state)
    if self.board.lang ~= lang then self.board:randomGame(lang) end
    ScreenBase.init(self)
    if lang == "en" then
        UIManager:nextTick(function()
            if not self.closed and self.plugin:getSetting("lang", "en") == "en" then
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
    local title_bar = self:buildTitleBar(_("Wordle"), function()
        local items = {}
        if self.board.lang == "en" then
            items[#items + 1] = {
                text = T(_("Today's Wordle (%1)"), NYT.today()),
                callback = function() self:onToday() end,
            }
            items[#items + 1] = {
                text = _("Play another day's Wordle"),
                callback = function() self:openDateInput() end,
            }
            items[#items + 1] = {
                text = _("Offline random word"), callback = function() self:onNewGame() end,
            }
        else
            items[#items + 1] = { text = _("New game"), callback = function() self:onNewGame() end }
        end
        items[#items + 1] = { text = self:_langLabel(), callback = function() self:openLangMenu() end }
        items[#items + 1] = self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR)
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
        layout    = (self.board.lang == "fr") and "azerty" or "qwerty",
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

function WordleScreen:onNewGame()
    self.board:randomGame(self.plugin:getSetting("lang", "en"))
    self:saveAndRefresh()
end

function WordleScreen:saveAndRefresh()
    self.plugin:saveState(self:serializeState())
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

-- - daily puzzles ------------------------------------------------------------

function WordleScreen:onToday(on_cancel)
    self:playDate(NYT.today(), on_cancel)
end

function WordleScreen:playDate(date, on_cancel)
    if self.closed or self.fetching then return end
    if not NYT.isValidDate(date) then
        UIManager:show(InfoMessage:new{ text = _("Enter a valid date in YYYY-MM-DD format, no later than today.") })
        return
    end
    if self.board:selectDate(date) then
        self:saveAndRefresh()
        return
    end

    self.fetching = true
    local Trapper = require("ui/trapper")
    Trapper:wrap(function()
        local completed, solution, err = Trapper:dismissableRunInSubprocess(function()
            return NYT.fetch(date)
        end, T(_("Loading Wordle for %1…"), date))
        self.fetching = false
        if self.closed then return end
        if not completed then
            if on_cancel then on_cancel() end
            return
        end
        if solution then
            self.board:selectDate(date, solution)
            self:saveAndRefresh()
        else
            self:onNewGame()
            UIManager:show(InfoMessage:new{
                text = T(_("Could not load NYT Wordle for %1 (%2). Playing an offline random word instead."),
                    date, err or _("No response")),
            })
        end
    end)
end

function WordleScreen:openDateInput()
    local dialog
    dialog = InputDialog:new{
        title = _("Play another day's Wordle"),
        input = self.board.puzzle_date or NYT.today(),
        input_type = "string",
        description = T(_("YYYY-MM-DD — device date: %1"), NYT.today()),
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Play"), is_enter_default = true, callback = function()
                local date = dialog:getInputValue()
                if not NYT.isValidDate(date) then
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

function WordleScreen:openLangMenu()
    local items = {
        { id = "en", text = _("English") },
        { id = "fr", text = _("Français") },
    }
    MenuHelper.openPickerMenu{
        title      = _("Language"),
        items      = items,
        current_id = self.plugin:getSetting("lang", "en"),
        parent     = self,
        on_select  = function(lang)
            local previous_lang = self.plugin:getSetting("lang", "en")
            self.plugin:saveSetting("lang", lang)
            if self.lang_btn then
                self.lang_btn:setText(self:_langLabel(), self.lang_btn.width)
            end
            if lang == "en" then
                self:onToday(function()
                    self.plugin:saveSetting("lang", previous_lang)
                    self:saveAndRefresh()
                end)
            else
                self:onNewGame()
            end
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
    elseif self.board.lang == "en" then
        status = _("Offline random word") .. " — " .. status
    end
    ScreenBase.updateStatus(self, status)
end

function WordleScreen:_langLabel()
    local lang = self.plugin:getSetting("lang", "en")
    return lang == "fr" and "FR" or "EN"
end

return WordleScreen
