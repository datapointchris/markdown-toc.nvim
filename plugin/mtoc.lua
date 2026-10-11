if vim.g.loaded_mtoc then
  return
end
vim.g.loaded_mtoc = 1

vim.api.nvim_create_user_command('Mtoc', function(opts)
  require('mtoc').run(opts)
end, {
  nargs = '?',
  range = true,
  bang = true,
  complete = function()
    return require('mtoc').commands
  end,
})

require('mtoc').register_autocmds()
