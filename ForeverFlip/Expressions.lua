local F = ForeverFlip
local U = F.Util
local E = {}
F.Expr = E
-- Deliberately small expression grammar. No Lua compiler or executable input.
function E.eval(text, sources)
    if type(text) ~= "string" or #text > 1024 then
        return nil, "Formula too long"
    end
    local ok, value = pcall(function()
        local t = {}
        local i = 1
        while i <= #text do
            local rest = text:sub(i)
            local ws = rest:match("^%s+")
            if ws then
                i = i + #ws
            else
                local n = rest:match("^%d+%.?%d*") or rest:match("^%.%d+")
                local id = rest:match("^[%a_][%w_]*")
                local token = n or id or rest:sub(1, 1)
                if not n and not id and not token:match("^[%+%-%*/%^%%%(%)%,]$") then
                    error("Invalid token")
                end
                t[#t + 1] = token:lower()
                i = i + #token
                if #t > 256 then
                    error("Too many tokens")
                end
            end
        end
        local p, depth = 1, 0
        local expr, unary
        local function checked(v)
            if v == nil then
                return nil
            end
            if not U.finite(v) or math.abs(v) > 1e15 then
                error("Numeric range")
            end
            return v
        end
        local function primary()
            depth = depth + 1
            if depth > 48 then
                error("Formula nesting")
            end
            local token = t[p]
            p = p + 1
            local v
            if token == "(" then
                v = expr()
                if t[p] ~= ")" then
                    error("Missing closing bracket")
                end
                p = p + 1
            elseif tonumber(token) then
                v = tonumber(token)
                local unit = t[p]
                if unit == "g" or unit == "s" or unit == "c" then
                    v = v * (unit == "g" and 10000 or unit == "s" and 100 or 1)
                    p = p + 1
                end
            elseif token and token:match("^[%a_]") then
                if t[p] == "(" then
                    p = p + 1
                    local args = {}
                    local count = 0
                    if t[p] ~= ")" then
                        repeat
                            count = count + 1
                            if count > 32 then
                                error("Arguments")
                            end
                            args[count] = expr()
                            if t[p] ~= "," then
                                break
                            end
                            p = p + 1
                        until false
                    end
                    if t[p] ~= ")" then
                        error("Function bracket")
                    end
                    p = p + 1
                    if token == "min" or token == "max" or token == "avg" or token == "first" then
                        local sum, n = 0, 0
                        for j = 1, count do
                            local a = args[j]
                            if a ~= nil then
                                n = n + 1
                                sum = sum + a
                                if token == "first" then
                                    v = v or a
                                elseif token == "min" then
                                    v = v and math.min(v, a) or a
                                elseif token == "max" then
                                    v = v and math.max(v, a) or a
                                end
                            end
                        end
                        if token == "avg" then
                            v = n > 0 and sum / n or nil
                        end
                    elseif
                        token == "ifgt"
                        or token == "ifgte"
                        or token == "iflt"
                        or token == "iflte"
                        or token == "ifeq"
                    then
                        if args[1] and args[2] then
                            local a, b = args[1], args[2]
                            local yes = (token == "ifgt" and a > b)
                                or (token == "ifgte" and a >= b)
                                or (token == "iflt" and a < b)
                                or (token == "iflte" and a <= b)
                                or (token == "ifeq" and a == b)
                            if yes then
                                v = args[3]
                            else
                                v = args[4]
                            end
                        end
                    elseif token == "check" then
                        if args[1] then
                            if args[1] > 0 then
                                v = args[2]
                            else
                                v = args[3]
                            end
                        end
                    elseif token == "round" or token == "roundup" or token == "rounddown" then
                        local step = args[2] or 1
                        if args[1] and step > 0 then
                            local x = args[1] / step
                            v = (
                                token == "roundup" and math.ceil(x)
                                or token == "rounddown" and math.floor(x)
                                or math.floor(x + 0.5)
                            ) * step
                        end
                    else
                        error("Unknown function: " .. token)
                    end
                else
                    v = (sources or {})[token]
                end
            else
                error("Expected a price or source")
            end
            depth = depth - 1
            return checked(v)
        end
        unary = function()
            if t[p] == "-" then
                p = p + 1
                local v = unary()
                return v and -v
            end
            if t[p] == "+" then
                p = p + 1
                return unary()
            end
            local v = primary()
            if t[p] == "%" then
                p = p + 1
                local r = unary()
                v = v and r and v / 100 * r
            end
            return v
        end
        local function product()
            local v = unary()
            while t[p] == "*" or t[p] == "/" or t[p] == "^" do
                local op = t[p]
                p = p + 1
                local r = unary()
                if v == nil or r == nil then
                    v = nil
                elseif op == "*" then
                    v = v * r
                elseif op == "/" then
                    if r == 0 then
                        error("Division by zero")
                    end
                    v = v / r
                else
                    if math.abs(r) > 16 then
                        error("Exponent range")
                    end
                    v = v ^ r
                end
                checked(v)
            end
            return v
        end
        expr = function()
            local v = product()
            while t[p] == "+" or t[p] == "-" do
                local op = t[p]
                p = p + 1
                local r = product()
                if v == nil or r == nil then
                    v = nil
                else
                    v = op == "+" and v + r or v - r
                end
                checked(v)
            end
            return v
        end
        local result = expr()
        if p <= #t then
            error("Unexpected token")
        end
        return checked(result)
    end)
    if not ok then
        return nil, tostring(value)
    end
    return value, value == nil and "Unknown price source" or nil
end
