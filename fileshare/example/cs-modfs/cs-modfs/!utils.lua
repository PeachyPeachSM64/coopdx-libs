local json = require("lib/json")

function log_message(msg)
    local s = string.format("[%06d] %s", get_global_timer(), msg)
    print(s)
    djui_chat_message_create(s)
end

function table.removeN(t, n)
    local t2 = {}
    for i = n + 1, #t do
        t2[i - n] = t[i]
    end
    return t2
end

function table.walk(t, func)
    for k, v in pairs(t) do
        if type(v) == "table" then
            table.walk(v, func)
        else
            func(t, k, v)
        end
    end
end

function table.find(t, func)
    for k, v in pairs(t) do
        if func(k, v) then
            return k
        end
    end
    return nil
end

function table.count(t)
    local c = 0
    for _, _ in pairs(t) do
        c = c + 1
    end
    return c
end

function table.tostring(t, tabsize, tabs)
    local s
    if type(t) == "table" then
        s = "{"
        if not rawequal(next(t), nil) then
            s = s .. "\n"
            for k, v in pairs(t) do
                s = s ..
                    string.rep(" ", tabsize * (tabs + 1)) ..
                    table.tostring(k, tabsize, tabs + 1) ..
                    " = " ..
                    table.tostring(v, tabsize, tabs + 1) ..
                    ",\n"
            end
        end
        s = s .. string.rep(" ", tabsize * tabs) .. "}"
    elseif type(t) == "string" then
        s = "\"" .. t .. "\""
    else
        s = tostring(t)
    end
    return s
end

function string.startswith(s, prefix)
    return string.sub(s, 1, #prefix) == prefix
end

function string.endswith(s, suffix)
    return string.sub(s, 1 + #s - #suffix) == suffix
end

function read_json_file(modFs, filename)
    if modFs then
        local file = modFs:get_file(filename)
        if file then
            file:set_text_mode(true)
            file:rewind()
            local data = file:read_string()
            return json.decode(data)
        end
    end
    return nil
end

function print_character_data(c)
    print(table.tostring(c, 2, 0))
end
