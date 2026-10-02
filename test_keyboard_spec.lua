local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

describe("German keyboard layout wiring", function()
    local Keyboard, previous, buttons, rows
    local names = {
        "ui/widget/button", "ui/widget/container/centercontainer", "ui/geometry",
        "ui/widget/horizontalgroup", "ui/widget/horizontalspan", "ui/size",
        "ui/widget/verticalgroup", "ui/widget/verticalspan",
    }

    before_each(function()
        previous, buttons, rows = {}, {}, {}
        local Widget = { new = function(_, opts) return opts end }
        for _, name in ipairs(names) do
            previous[name] = package.loaded[name]
            package.loaded[name] = Widget
        end
        package.loaded["ui/size"] = {
            span = { horizontal_small = 4, vertical_default = 4 },
            border = { button = 1 }, radius = { button = 0 }, padding = { button = 2 },
        }
        package.loaded["ui/widget/button"] = { new = function(_, opts)
            buttons[#buttons + 1] = opts
            return opts
        end }
        package.loaded["ui/widget/horizontalgroup"] = { new = function(_, opts)
            local width = 0
            for _, widget in ipairs(opts) do width = width + widget.width end
            rows[#rows + 1] = { items = opts, width = width }
            opts.getSize = function() return { w = width, h = 30 } end
            return opts
        end }
        Keyboard = assert(loadfile(DIR .. "keyboard_widget.lua"))()
    end)

    after_each(function()
        for _, name in ipairs(names) do package.loaded[name] = previous[name] end
    end)

    it("fits German rows in portrait and landscape keyboard allocations", function()
        for _, width in ipairs({ 228, 540 }) do
            rows = {}
            Keyboard.build{ width = width, layout = "qwertz", enter = true, backspace = true,
                onKey = function() end }
            assert.are.equal(3, #rows)
            for _, row in ipairs(rows) do
                assert.is_true(row.width <= width)
                for _, item in ipairs(row.items) do assert.is_true(item.width > 0) end
            end
        end
    end)

    it("wires umlauts and sharp S to input and per-letter shading", function()
        local pressed = {}
        Keyboard.build{ width = 540, layout = "qwertz", enter = true, backspace = true,
            onKey = function(key) pressed[#pressed + 1] = key end,
            keyColor = function(key) if key == "ß" then return "correct" end end,
        }
        local by_key = {}
        for _, button in ipairs(buttons) do by_key[button.text] = button end
        for _, key in ipairs({ "Ä", "Ö", "Ü", "ß", "⌫", "↵" }) do
            assert.is_not_nil(by_key[key])
            by_key[key].callback()
        end
        assert.are.same({ "Ä", "Ö", "Ü", "ß", "⌫", "↵" }, pressed)
        assert.are.equal("correct", by_key["ß"].background)
        assert.is_nil(by_key["↵"].background)
        assert.are.equal("Z", rows[1].items[11].text)
        assert.are.equal("Y", rows[3].items[1].text)
    end)
end)
