local M = {}

local tcp = nil

local queue = {}
local curChunk = ""

local function handleLine(line)
    if line == "" then
        return
    end
end

local function handleChunk(chunk)
    if string.match(chunk, '\r\n') ~= nil then
        local lines = vim.split(chunk, '\r\n')

        curChunk = curChunk .. lines[1]

        queue[#queue + 1] = curChunk

        curChunk = ""

        for i, line in ipairs(lines) do
            -- ignore the first one (handled above)
            if i > 1 then
                queue[#queue+1] = line
            end
        end
    else
        curChunk = curChunk .. chunk
    end

    for _, line in ipairs(queue) do
        handleLine(line)
    end
    queue = {}
end

function M.connect(server, port)
    if tcp ~= nil then
        vim.notify("Already connected to an irc server", vim.log.levels.ERROR)
        return
    end

    port = port or 6667

    tcp  = vim.uv.new_tcp()
    tcp:connect(server, port, function(err)
        tcp:read_start(function (err, chunk)
            assert(not err, err)

            if chunk then
                handleChunk(chunk)
            else
                tcp:shutdown()
                tcp:close()
            end
        end)
    end)
end

return M
