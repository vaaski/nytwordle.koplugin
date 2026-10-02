-- Plugin-local keyboard: English QWERTY and German QWERTZ, including ÄÖÜß.
local Button          = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Geom            = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")

local Keyboard = {}
Keyboard.ROWS_QWERTY = {
    { "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P" },
    { "A", "S", "D", "F", "G", "H", "J", "K", "L" },
    { "Z", "X", "C", "V", "B", "N", "M" },
}
Keyboard.ROWS_QWERTZ = {
    { "Q", "W", "E", "R", "T", "Z", "U", "I", "O", "P", "Ü" },
    { "A", "S", "D", "F", "G", "H", "J", "K", "L", "Ö", "Ä" },
    { "Y", "X", "C", "V", "B", "N", "M", "ß" },
}

-- - layout -------------------------------------------------------------------

local function isSpecial(key)
    return key == "⌫" or key == "↵"
end

function Keyboard.build(opts)
    local base = opts.layout == "qwertz" and Keyboard.ROWS_QWERTZ or Keyboard.ROWS_QWERTY
    local rows = {}
    for i, row in ipairs(base) do
        rows[i] = { table.unpack(row) }
    end
    if opts.backspace then table.insert(rows[1], "⌫") end
    if opts.enter then table.insert(rows[2], "↵") end

    local gap = Size.span.horizontal_small
    local key_width
    for _, row in ipairs(rows) do
        local units = 0
        for _, key in ipairs(row) do units = units + (isSpecial(key) and 1.4 or 1) end
        local width = math.floor((opts.width - gap * (#row - 1)) / units)
        key_width = math.min(key_width or width, width)
    end

    local keyboard = VerticalGroup:new{ align = "center" }
    for i, row in ipairs(rows) do
        if i > 1 then
            table.insert(keyboard, VerticalSpan:new{ width = Size.span.vertical_default })
        end
        local items = {}
        for j, key in ipairs(row) do
            local special = isSpecial(key)
            table.insert(items, Button:new{
                text = key,
                width = special and math.floor(key_width * 1.4) or key_width,
                bordersize = Size.border.button,
                radius = Size.radius.button,
                margin = 0,
                padding = Size.padding.button,
                background = not special and opts.keyColor and opts.keyColor(key) or nil,
                callback = function() opts.onKey(key) end,
            })
            if j < #row then table.insert(items, HorizontalSpan:new{ width = gap }) end
        end
        local group = HorizontalGroup:new(items)
        table.insert(keyboard, CenterContainer:new{
            dimen = Geom:new{ w = opts.width, h = group:getSize().h },
            group,
        })
    end
    return keyboard
end

return Keyboard
