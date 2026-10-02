local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

describe("NYT screen workflow", function()
    local Screen, plugin, messages, queued, requests, responses, previous
    local names = {
        "ffi/blitbuffer", "device", "ui/widget/container/framecontainer",
        "ui/widget/horizontalgroup", "ui/widget/horizontalspan", "ui/size",
        "ui/uimanager", "ui/widget/verticalgroup", "ui/widget/verticalspan",
        "ui/widget/infomessage", "ui/widget/inputdialog", "i18n", "ffi/util",
        "screen_base", "menu_helper", "ui/trapper",
        DIR .. "common/keyboard_widget", DIR .. "board_widget", DIR .. "nyt",
    }

    before_each(function()
        previous = {}
        for _, name in ipairs(names) do
            previous[name] = package.loaded[name]
            package.loaded[name] = {}
        end
        messages, queued, requests, responses = {}, {}, {}, {}
        local Widget = { new = function(_, opts) return opts end }
        package.loaded["ui/widget/infomessage"] = Widget
        package.loaded["ui/widget/inputdialog"] = {
            new = function(_, opts)
                opts.getInputValue = function(self) return self.input end
                opts.onShowKeyboard = function() end
                return opts
            end,
        }
        package.loaded["i18n"] = function(text) return text end
        package.loaded["ffi/util"] = { template = function(text, ...)
            for i, value in ipairs({ ... }) do text = text:gsub("%%" .. i, tostring(value)) end
            return text
        end }
        package.loaded["ui/uimanager"] = {
            nextTick = function(_, callback) queued[#queued + 1] = callback end,
            setDirty = function() end,
            show = function(_, widget) messages[#messages + 1] = widget end,
            close = function() end,
        }
        package.loaded["screen_base"] = {
            extend = function(_, opts)
                opts.__index = opts
                opts.new = function(self, values)
                    local obj = setmetatable(values, self)
                    obj:init()
                    return obj
                end
                return opts
            end,
            init = function(self) self:buildLayout() end,
            closeScreen = function(self) self.plugin:saveState(self:serializeState()) end,
        }
        package.loaded["ui/trapper"] = {
            wrap = function(_, callback) callback() end,
            dismissableRunInSubprocess = function(_, callback) return true, callback() end,
        }
        local nyt = assert(loadfile(DIR .. "nyt.lua"))()
        nyt.today = function() return "2024-01-02" end
        nyt.fetch = function(date)
            requests[#requests + 1] = date
            return responses[date], "timeout"
        end
        package.loaded[DIR .. "nyt"] = nyt
        Screen = assert(loadfile(DIR .. "screen.lua"))()
        Screen.buildLayout = function() end
        plugin = {
            lang = "en",
            loadState = function(self) return self.state end,
            saveState = function(self, state) self.state = state end,
            getSetting = function(self) return self.lang end,
            saveSetting = function(self, _, lang) self.lang = lang end,
        }
    end)

    after_each(function()
        for _, name in ipairs(names) do package.loaded[name] = previous[name] end
    end)

    it("opens local today instead of yesterday and resumes today's partial row", function()
        responses["2024-01-01"] = "APPLE"
        responses["2024-01-02"] = "ABOUT"
        local screen = Screen:new{ plugin = plugin }
        screen:playDate("2024-01-01")
        queued[1]()
        assert.are.equal("2024-01-02", screen.board.puzzle_date)
        screen.board:typeLetter("A")
        screen:closeScreen()
        local reopened = Screen:new{ plugin = plugin }
        queued[2]()
        assert.are.same({ "A" }, reopened.board.current)
        assert.are.equal(2, #requests)
    end)

    it("falls back to a labeled undated random game and retries on reopening", function()
        local screen = Screen:new{ plugin = plugin }
        queued[1]()
        assert.is_nil(screen.board.puzzle_date)
        assert.are.equal(5, #screen.board.secret)
        assert.is_truthy(messages[1].text:find("offline random word", 1, true))
        assert.is_nil(plugin.state.dated_games["2024-01-02"])
        screen:closeScreen()
        responses["2024-01-02"] = "ABOUT"
        local reopened = Screen:new{ plugin = plugin }
        queued[2]()
        assert.are.equal("ABOUT", reopened.board.secret)
    end)

    it("validates date input before requesting and accepts a corrected date", function()
        local screen = Screen:new{ plugin = plugin }
        screen:openDateInput()
        local dialog = messages[1]
        assert.is_truthy(dialog.description:find("2024-01-02", 1, true))
        dialog.input = "2024-01-03"
        dialog.buttons[1][2].callback()
        assert.are.equal(0, #requests)
        responses["2024-01-01"] = "APPLE"
        dialog.input = "2024-01-01"
        dialog.buttons[1][2].callback()
        assert.are.equal("2024-01-01", screen.board.puzzle_date)
    end)

    it("does not fetch after closing or when opening French", function()
        local screen = Screen:new{ plugin = plugin }
        screen:closeScreen()
        queued[1]()
        assert.are.equal(0, #requests)
        plugin.lang = "fr"
        Screen:new{ plugin = plugin }
        assert.are.equal(1, #queued)
    end)

    it("does not replace French if language changes before the startup callback", function()
        local screen = Screen:new{ plugin = plugin }
        plugin.lang = "fr"
        screen:onNewGame()
        queued[1]()
        assert.are.equal("fr", screen.board.lang)
        assert.are.equal(0, #requests)
    end)

    it("keeps the current game when fetching is cancelled", function()
        local screen = Screen:new{ plugin = plugin }
        responses["2024-01-01"] = "APPLE"
        screen:playDate("2024-01-01")
        screen.board:typeLetter("A")
        package.loaded["ui/trapper"].dismissableRunInSubprocess = function() return false end
        screen:playDate("2024-01-02")
        assert.are.equal("2024-01-01", screen.board.puzzle_date)
        assert.are.same({ "A" }, screen.board.current)
        assert.is_false(screen.fetching)
        assert.are.equal(0, #messages)
    end)

    it("restores the French preference when an English language switch is cancelled", function()
        plugin.lang = "fr"
        local screen = Screen:new{ plugin = plugin }
        screen.board:typeLetter("A")
        local picker
        package.loaded["menu_helper"].openPickerMenu = function(opts) picker = opts end
        package.loaded["ui/trapper"].dismissableRunInSubprocess = function() return false end
        screen:openLangMenu()
        picker.on_select("en")
        assert.are.equal("fr", plugin.lang)
        assert.are.equal("fr", screen.board.lang)
        assert.are.same({ "A" }, screen.board.current)
    end)
end)
