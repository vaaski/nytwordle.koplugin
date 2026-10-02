local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = DIR .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(DIR .. name .. ".lua"))()
    end
    return package.loaded[key]
end
local Dates = lrequire("dates")
local Letters = lrequire("letters")
local HTTP = lrequire("puzzle_http")
local Spiegel = { lang = "de", name = "SPIEGEL", first_date = "2024-12-14" }
local URL = "https://api.spiegel.raetselzentrale.com/api/v3/l/spiegel/wordlearchiv"

function Spiegel.today()
    return Dates.germanyToday()
end

function Spiegel.isValidDate(date, today)
    return Dates.isValid(date, today or Spiegel.today()) and date >= Spiegel.first_date
end

-- - response decoding --------------------------------------------------------

function Spiegel.decode(response, requested_date)
    if type(response) ~= "table" or type(response.data) ~= "table" then return nil end
    local data = response.data
    if type(data.ckey) ~= "string" or type(data.riddle) ~= "table" then return nil end
    local year, month, day = data.ckey:match("^l_spiegel_wordlearchiv_(%d%d%d%d)(%d%d)(%d%d)_%d+$")
    if not year then return nil end
    local date = year .. "-" .. month .. "-" .. day
    if not Dates.isValid(date) or date < Spiegel.first_date
            or (requested_date and date ~= requested_date) then return nil end

    local payload = data.riddle.payload
    if type(payload) ~= "table" or payload.width ~= 5 or payload.height ~= 6
            or type(payload.grid) ~= "table" or #payload.grid ~= 30 then return nil end
    local rows = { {}, {}, {}, {}, {}, {} }
    for _, cell in ipairs(payload.grid) do
        if type(cell) ~= "table" or type(cell.row) ~= "number" or type(cell.col) ~= "number"
                or cell.row % 1 ~= 0 or cell.col % 1 ~= 0
                or cell.row < 0 or cell.row > 5 or cell.col < 0 or cell.col > 4
                or cell.type ~= "answer" or type(cell.items) ~= "table" then return nil end
        local letter
        for _, item in ipairs(cell.items) do
            if type(item) ~= "table" then return nil end
            if item.type == "value" then
                if letter or type(item.value) ~= "string" then return nil end
                letter = Letters.upper(item.value)
                if not Letters.isLetter(letter, "de") then return nil end
            end
        end
        local row = rows[cell.row + 1]
        if not letter or row[cell.col + 1] then return nil end
        row[cell.col + 1] = letter
    end
    local solution = table.concat(rows[1])
    if not Letters.isWord(solution, "de") then return nil end
    for _, row in ipairs(rows) do
        if table.concat(row) ~= solution then return nil end
    end
    return solution, date
end

-- Without a date, the API determines today's puzzle using its own clock.
function Spiegel.fetch(date)
    -- The screen checks the future against its authoritative server date.
    if date and (not Dates.isValid(date) or date < Spiegel.first_date) then
        return nil, "Invalid date"
    end
    local url = URL
    if date then url = url .. "/" .. date:gsub("-", "") end
    local data, err = HTTP.get(url .. "?channel=www.spiegel.de")
    if not data then return nil, err end
    local solution, puzzle_date = Spiegel.decode(data, date)
    if not solution then return nil, "Invalid puzzle response" end
    return solution, nil, puzzle_date
end

return Spiegel
