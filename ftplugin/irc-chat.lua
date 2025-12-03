local bname = vim.api.nvim_buf_get_name(0)

local irc = require "irc"

vim.bo.buftype = 'nofile'


local domain, channel, is_send = irc.parse_url(bname)
if not irc.connected() and not is_send then
    -- if we're not connected, dont try to connect to a channel yet
    vim.api.nvim_buf_set_name(0, 'irc://' .. domain .. '#[system]')
    irc.connect(bname, vim.fn.bufnr())
elseif irc.connected() then
    local recvbuf, sendbuf = irc.join_and_make_buffers(channel, {
        recv = vim.fn.bufnr()
    })
    vim.api.nvim_open_win(sendbuf, true, {
        vertical = false,
        height = 10,
    })
end
