local bname = vim.api.nvim_buf_get_name(0)

local irc = require "irc"

local domain, channel, is_send = irc.parse_url(bname)
if not irc.connected() and channel == nil then
    vim.api.nvim_buf_set_name(0, 'irc://' .. domain .. '#[system]')
    irc.connect(bname, vim.fn.bufnr())
end
