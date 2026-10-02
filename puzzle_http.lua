local HTTP = {}

function HTTP.get(url)
    -- KOReader provides HTTPS support through socket.http and socketutil.
    local ok, data, err = pcall(function()
        local http = require("socket.http")
        local socketutil = require("socketutil")
        local json = require("json")
        local body = {}
        local block, total = socketutil.block_timeout, socketutil.total_timeout
        socketutil:set_timeout(5, 15)
        local success, result, code = pcall(http.request, {
            url = url,
            headers = { ["Accept"] = "application/json" },
            sink = socketutil.table_sink(body),
        })
        socketutil:set_timeout(block, total)

        if not success then return nil, "Network request failed" end
        if not result then return nil, tostring(code or "No response") end
        if tonumber(code) ~= 200 then return nil, "HTTP " .. tostring(code) end
        local decoded, value = pcall(json.decode, table.concat(body))
        if not decoded or type(value) ~= "table" then return nil, "Invalid puzzle response" end
        return value
    end)
    if not ok then return nil, "Could not retrieve puzzle" end
    return data, err
end

return HTTP
