local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

describe("NYT screen workflow", function()
    local Screen, plugin, messages, queued, requests, responses, previous
    local names = {
        "ffi/blitbuffer", "device", "ui/widget/container/framecontainer",
        "ui/widget/horizontalgroup", "ui/widget/horizontalspan", "ui/size",
        "ui/uimanager", "ui/widget/verticalgroup", "ui/widget/verticalspan",
        "ui/widget/infomessage", "ui/widget/inputdialog", "i18n", "ffi/util",
        "screen_base", "menu_helper", "ui/trapper",
         DIR .. "keyboard_widget", DIR .. "board_widget", DIR .. "nyt", DIR .. "spiegel",
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
        local spiegel = assert(loadfile(DIR .. "spiegel.lua"))()
        spiegel.today = function() return "2026-10-02" end
        spiegel.fetch = function(date)
            local key = "de:" .. (date or "today")
            requests[#requests + 1] = key
            return responses[key], "timeout", date or "2026-10-02"
        end
        package.loaded[DIR .. "spiegel"] = spiegel
        Screen = assert(loadfile(DIR .. "screen.lua"))()
        Screen.buildLayout = function() end
        plugin = {
            mode = "nyt",
            loadState = function(self) return self.state end,
            saveState = function(self, state) self.state = state end,
            getSetting = function(self, key, default)
                if self[key] == nil then return default end
                return self[key]
            end,
            saveSetting = function(self, key, value) self[key] = value end,
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
        assert.is_nil(plugin.state.dated_games["en:2024-01-02"])
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

    it("does not fetch after closing or when opening explicit offline play", function()
        local screen = Screen:new{ plugin = plugin }
        screen:closeScreen()
        queued[1]()
        assert.are.equal(0, #requests)
        plugin.offline = true
        Screen:new{ plugin = plugin }
        assert.are.equal(1, #queued)
    end)

    it("does not replace offline play selected before the startup callback", function()
        local screen = Screen:new{ plugin = plugin }
        screen:onNewGame(true)
        queued[1]()
        assert.are.equal("en", screen.board.lang)
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

    it("restores the provider and offline preference when switching is cancelled", function()
        plugin.mode = "spiegel"
        plugin.offline = true
        local screen = Screen:new{ plugin = plugin }
        screen.board:typeLetter("A")
        local picker
        package.loaded["menu_helper"].openPickerMenu = function(opts) picker = opts end
        package.loaded["ui/trapper"].dismissableRunInSubprocess = function() return false end
        screen:openModeMenu()
        picker.on_select("nyt")
        assert.are.equal("spiegel", plugin.mode)
        assert.is_true(plugin.offline)
        assert.are.equal("de", screen.board.lang)
        assert.are.same({ "A" }, screen.board.current)
    end)

    it("opens SPIEGEL's server date and resumes its cached progress", function()
        plugin.mode = "spiegel"
        package.loaded[DIR .. "spiegel"].today = function() return "2026-09-30" end
        responses["de:today"] = "GRÜNE"
        local screen = Screen:new{ plugin = plugin }
        queued[1]()
        assert.are.equal("2026-10-02", screen.board.puzzle_date)
        assert.are.equal("2026-10-02", screen:today())
        screen.board:typeLetter("Ü")
        screen:closeScreen()
        local reopened = Screen:new{ plugin = plugin }
        queued[2]()
        assert.are.same({ "Ü" }, reopened.board.current)
        assert.are.equal("de", reopened.board.lang)
    end)

    it("uses a cached German daily game when the current endpoint is unavailable", function()
        plugin.mode = "spiegel"
        responses["de:2026-10-02"] = "GRÜNE"
        local screen = Screen:new{ plugin = plugin }
        screen:playDate("2026-10-02")
        screen.board:typeLetter("G")
        queued[1]()
        assert.are.equal("2026-10-02", screen.board.puzzle_date)
        assert.are.same({ "G" }, screen.board.current)
        assert.is_false(plugin.offline)
        assert.are.equal(0, #messages)
    end)

    it("advances the server date across device midnight without losing the clock offset", function()
        plugin.mode = "spiegel"
        local device_date = "2026-09-30"
        package.loaded[DIR .. "spiegel"].today = function() return device_date end
        responses["de:today"] = "GRÜNE"
        local screen = Screen:new{ plugin = plugin }
        queued[1]()
        device_date = "2026-10-01"
        assert.are.equal("2026-10-03", screen:today())
        screen:playDate("2026-10-02")
        assert.are.equal("2026-10-02", screen.board.puzzle_date)
        assert.are.equal(1, #requests)
    end)

    it("keeps explicit German offline games offline after reopening", function()
        plugin.mode = "spiegel"
        local screen = Screen:new{ plugin = plugin }
        screen:onNewGame(true)
        screen.board:typeLetter("Ä")
        queued[1]()
        screen:closeScreen()
        local reopened = Screen:new{ plugin = plugin }
        assert.are.same({ "Ä" }, reopened.board.current)
        assert.is_nil(reopened.board.puzzle_date)
        assert.are.equal(1, #queued)
        assert.are.equal(0, #requests)
    end)

    it("falls back to German words without making the fallback an explicit offline preference", function()
        plugin.mode = "spiegel"
        local screen = Screen:new{ plugin = plugin }
        queued[1]()
        assert.are.equal("de", screen.board.lang)
        assert.is_nil(screen.board.puzzle_date)
        assert.is_false(plugin.offline)
        assert.is_truthy(messages[1].text:find("SPIEGEL", 1, true))
    end)
end)
