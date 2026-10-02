local Dates = {}

function Dates.localToday()
    return os.date("%Y-%m-%d")
end

function Dates.isValid(date, today)
    if type(date) ~= "string" then return false end
    local year, month, day = date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not year then return false end
    year, month, day = tonumber(year), tonumber(month), tonumber(day)
    if year < 1 or month < 1 or month > 12 or day < 1 then return false end
    local days = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    if year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0) then days[2] = 29 end
    return day <= days[month] and (not today or date <= today)
end

-- - Europe/Berlin ------------------------------------------------------------

-- Gregorian days since 1970-01-01, independent of the device's timezone.
local function daysFromCivil(year, month, day)
    if month <= 2 then year = year - 1 end
    local era = math.floor(year / 400)
    local yoe = year - era * 400
    local adjusted_month = month + (month > 2 and -3 or 9)
    local doy = math.floor((153 * adjusted_month + 2) / 5) + day - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

local function transition(year, month)
    local last_day = daysFromCivil(year, month, 31)
    -- Sunday is day zero; daylight saving changes at 01:00 UTC.
    local sunday = last_day - (last_day + 4) % 7
    return sunday * 86400 + 3600
end

local function dateDays(date)
    local year, month, day = date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    return daysFromCivil(tonumber(year), tonumber(month), tonumber(day))
end

function Dates.advance(date, device_date_at_fetch, device_date_now)
    local elapsed_days = math.max(0, dateDays(device_date_now) - dateDays(device_date_at_fetch))
    return os.date("!%Y-%m-%d", (dateDays(date) + elapsed_days) * 86400)
end

function Dates.germanyToday(timestamp)
    timestamp = timestamp or os.time()
    local year = tonumber(os.date("!%Y", timestamp))
    local offset = 3600
    if timestamp >= transition(year, 3) and timestamp < transition(year, 10) then
        offset = 7200
    end
    return os.date("!%Y-%m-%d", timestamp + offset)
end

return Dates
