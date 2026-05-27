local aug = vim.api.nvim_create_augroup("irc.nvim", { clear = true })

vim.api.nvim_create_user_command("IRCChan", function(data)
    local irc = require"irc"
    irc.join(data.args)
end, { nargs = 1 })

vim.api.nvim_create_user_command("IRCNick", function(data)
    require"irc".nick(data.args)
end, { nargs = "+" })
