vim.api.nvim_create_user_command("IRCStart", function()
    require"irc".connect("199.193.138.248", 6667)
end, {})
