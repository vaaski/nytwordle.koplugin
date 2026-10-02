local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = DIR .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(DIR .. name .. ".lua"))()
    end
    return package.loaded[key]
end
local Dates = lrequire("dates")
local HTTP = lrequire("puzzle_http")
local NYT = { lang = "en", name = "NYT", first_date = "2021-06-19" }

-- - dates --------------------------------------------------------------------

function NYT.today()
    return Dates.localToday()
end

function NYT.isValidDate(date, today)
    return Dates.isValid(date, today or NYT.today())
end

-- - retrieval ----------------------------------------------------------------

function NYT.fetch(date)
    if not NYT.isValidDate(date) then return nil, "Invalid date" end

    local data, err = HTTP.get("https://www.nytimes.com/svc/wordle/v2/" .. date .. ".json")
    if not data then return nil, err end
    if data.print_date ~= date or type(data.solution) ~= "string"
            or not data.solution:match("^[a-zA-Z][a-zA-Z][a-zA-Z][a-zA-Z][a-zA-Z]$") then
        return nil, "Invalid puzzle response"
    end
    return data.solution:upper(), nil, date
end

return NYT
