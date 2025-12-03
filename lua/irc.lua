local M = {}

---@class Client
---@field tcp userdata | nil
---@field connected_host string | nil
---@field queue string[]
---@field curChunk string
---@field addr string
---@field port integer

local client = {
    tcp = nil,
    queue = {},
    curChunk = "",
    addr = "",
    port = 0,
    channel_bufs = {},
    nick = "",
    user = "",
    realname = "",

    motd = {}
}


local function handle_notice(user, text, out)
    vim.fn.appendbufline(out, '$', '<' .. vim.fn.slice(user, 1) .. '>: ' .. vim.fn.slice(text, 1))
end

local function handle_motd(line, out)
    vim.fn.appendbufline(out, '$', line)
end

local function nick_from_ircname(name)
    return vim.fn.slice(vim.split(name, "!")[1], 1)
end

---@param user string
---@param text string[]
local function handle_chan_msg(user, text, out)
    user = vim.split(user, '!')[1]
    user = vim.fn.slice(user, 1)
    vim.fn.appendbufline(out, '$', '<' .. user .. '>: ' .. vim.fn.slice(table.concat(vim.list_slice(text, 4), ' '), 1))
end

local function handleLine(line)
    local data = vim.split(line, ' ')

    if data[1] == "PING" then
        print("PONG")
        M.pong(data[2])
        return
    end

    local user = data[1]
    local command = data[2]
    local channel = data[3]

    vim.schedule(function()
        local recv_chan = M.get_chan('recv', channel or '[system]')

        if command == "NOTICE" then
            recv_chan = M.get_chan('recv', '[system]')
            handle_notice(user, table.concat(vim.list_slice(data, 4), ' '), recv_chan)
            return
        elseif command == "PRIVMSG" then
            if not vim.startswith(channel, '#') then
                -- we are in a dm, send data to a username buffer instead of channel buffer
                -- to keep it consistent
                recv_chan = M.get_chan('recv', nick_from_ircname(user))
            end
            handle_chan_msg(user, data, recv_chan)
        -- motd
        elseif command == '372' then
            recv_chan = M.get_chan('recv', '[system]')
            local motd_line = vim.fn.slice(table.concat(vim.list_slice(data, 4), ' '), 2)
            client.motd[#client.motd+1] = motd_line
            handle_motd(motd_line, recv_chan)
            return
        -- signal start of motd
        elseif command == '375' then
            recv_chan = M.get_chan('recv', '[system]')
            handle_motd('[-- BEGIN MOTD --]', recv_chan)
            return
        -- signal end of motd
        elseif command == '376' then
            recv_chan = M.get_chan('recv', '[system]')
            handle_motd('[-- END MOTD --]', recv_chan)
            return
        end

        recv_chan = M.get_chan('recv', '[system]')
        vim.fn.appendbufline(recv_chan, '$', line)
    end)
end

local function handleChunk(chunk)
    if string.match(chunk, '\r\n') ~= nil then
        local lines = vim.split(chunk, '\r\n')

        client.curChunk = client.curChunk .. lines[1]

        client.queue[#client.queue + 1] = client.curChunk

        client.curChunk = ""

        for i, line in ipairs(lines) do
            -- ignore the first one (handled above)
            if i > 1 then
                client.queue[#client.queue + 1] = line
            end
        end
    else
        client.curChunk = client.curChunk .. chunk
    end

    for _, line in ipairs(client.queue) do
        handleLine(line)
    end
    client.queue = {}
end

local function send(data)
    assert(client.tcp, 'not connected')
    client.tcp:write(data .. '\r\n')
end

function M.connected()
    return client.tcp ~= nil
end

function M.pong(pong)
    send("PONG :" .. pong)
end

function M.join(channel)
    send("JOIN " .. channel)
end

function M.nick(nick)
    client.nick = nick
    send("NICK " .. nick)
end

function M.user(user, realname)
    client.user = user
    client.realname = realname
    send("USER " .. user .. " 0 * :" .. realname)
end

function M.privmsg(channel, msg)
    send("PRIVMSG " .. channel .. " :" .. msg)
    handle_chan_msg(':' .. client.nick .. "!" .. client.user .. "@localhost", {'', '', '', ':' .. msg }, M.get_chan('recv', channel))
end

function M.join_and_make_buffers(channel, buffers)
    M.join(channel)

    local recvbuf = buffers.recv or vim.api.nvim_create_buf(true, false)
    local sendbuf = buffers.send or vim.api.nvim_create_buf(true, false)

    vim.api.nvim_buf_set_name(sendbuf, 'irc://>#' .. channel)
    vim.api.nvim_buf_set_name(recvbuf, 'irc://#' .. channel)

    vim.bo[sendbuf].buftype = 'acwrite'
    vim.api.nvim_create_autocmd('BufWriteCmd', {
        buffer = sendbuf,
        callback = function()
            local _, chan, is_send = M.parse_url(vim.api.nvim_buf_get_name(0))
            if is_send then
                for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
                    M.privmsg(chan, line)
                end
                vim.api.nvim_buf_set_lines(0, 0, -1, false, {})
            else
                vim.notify("NOT IN A SEND BUFFER", vim.log.levels.ERROR)
            end
        end
    })

    client.channel_bufs[channel] = {
        send = sendbuf,
        recv = recvbuf,
    }

    return recvbuf, sendbuf
end

function M.connect(url, systembuf)
    client.channel_bufs["[system]"] = {
        recv = systembuf
    }

    local domain, channel, _ = M.parse_url(url)

    client.tcp = vim.uv.new_tcp()
    client.tcp:connect(domain, 6667, function(err)
        assert(not err, err)

        local name = 'guest' .. tostring(math.random(5000, 10000))
        M.nick(name)
        M.user(name, name)
        client.tcp:read_start(function(err, chunk)
            if chunk then
                handleChunk(chunk)
            else
                client.tcp:shutdown()
                client.tcp:close()
            end
        end)
    end)
end

function M.parse_url(url)
    if not vim.startswith(url, "irc://") then
        error("URL must be in the form of irc://<server>, irc://#<user>, or irc://##<channel>")
    end

    local data

    local rest = vim.fn.slice(url, 6)

    local domain = nil
    local channel = ''
    local is_send = false
    if vim.startswith(rest, '#') then
        channel = vim.fn.slice(rest, 1)
        domain = client.addr
        goto done
    elseif vim.startswith(rest, '>') then
        rest = vim.fn.slice(rest, 1)
        is_send = true
        if vim.startswith(rest, '#') then
            channel = vim.fn.slice(rest, 1)
            domain = client.addr
            goto done
        end
    end

    -- handle full url

    data = vim.split(rest, '#')
    domain = data[1]
    channel = data[2]

    ::done::
    return domain, channel, is_send
end

function M.get_chan(ty, for_)
    local chans = client.channel_bufs[for_]
    if chans == nil then
        chans = {
            send = vim.api.nvim_create_buf(true, false),
            recv = vim.api.nvim_create_buf(true, false)
        }
        client.channel_bufs[for_] = chans
        vim.api.nvim_buf_set_name(chans.send, 'irc://>#' .. for_)
        vim.api.nvim_buf_set_name(chans.recv, 'irc://#' .. for_)
    end
    local chan = chans[ty]
    if chan == nil then
        chans[ty] = vim.api.nvim_create_buf(true, false)
        local name = 'irc://'
        if ty == 'send' then
            name = name .. '>'
        end
        name = name .. '#' .. for_
        vim.api.nvim_buf_set_name(chans[ty], name)
    end
    return chans and chans[ty] or nil
end

function M.motd()
    return client.motd
end

return M
