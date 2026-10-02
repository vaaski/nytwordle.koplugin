local NYT = {}

-- - dates --------------------------------------------------------------------

function NYT.today()
    return os.date("%Y-%m-%d")
end

function NYT.isValidDate(date, today)
    if type(date) ~= "string" then return false end
    local year, month, day = date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not year then return false end
    year, month, day = tonumber(year), tonumber(month), tonumber(day)
    if year < 1 or month < 1 or month > 12 or day < 1 then return false end

    local days = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    if year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0) then days[2] = 29 end
    return day <= days[month] and date <= (today or NYT.today())
end

-- - retrieval ----------------------------------------------------------------

function NYT.fetch(date)
    if not NYT.isValidDate(date) then return nil, "Invalid date" end

    -- Lazy dependencies keep date validation and the game model headless.
    local ok, solution, err = pcall(function()
        local http = require("socket.http")
        local socketutil = require("socketutil")
        local json = require("json")
        local body = {}
        local block_timeout, total_timeout = socketutil.block_timeout, socketutil.total_timeout
        socketutil:set_timeout(5, 15)
        local success, result, code = pcall(http.request, {
            url = "https://www.nytimes.com/svc/wordle/v2/" .. date .. ".json",
            headers = { ["Accept"] = "application/json" },
            sink = socketutil.table_sink(body),
        })
        socketutil:set_timeout(block_timeout, total_timeout)

        if not success then return nil, "Network request failed" end
        if not result then return nil, tostring(code or "No response") end
        if tonumber(code) ~= 200 then return nil, "HTTP " .. tostring(code) end

        local decoded, data = pcall(json.decode, table.concat(body))
        if not decoded or type(data) ~= "table"
                or data.print_date ~= date
                or type(data.solution) ~= "string"
                or not data.solution:match("^[a-zA-Z][a-zA-Z][a-zA-Z][a-zA-Z][a-zA-Z]$") then
            return nil, "Invalid puzzle response"
        end
        return data.solution:upper()
    end)
    if not ok then return nil, "Could not retrieve puzzle" end
    return solution, err
end

return NYT
