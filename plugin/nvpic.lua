if vim.g.loaded_nvpic then
  return
end
vim.g.loaded_nvpic = true

vim.api.nvim_create_user_command('NvpicPaste', function()
  require('nvpic').paste()
end, { desc = 'Paste image from clipboard' })

vim.api.nvim_create_user_command('NvpicPick', function()
  require('nvpic').pick()
end, { desc = 'Pick image from pics/' })

vim.api.nvim_create_user_command('NvpicToggle', function()
  require('nvpic').toggle()
end, { desc = 'Toggle image rendering' })

vim.api.nvim_create_user_command('NvpicRefresh', function()
  require('nvpic').refresh()
end, { desc = 'Refresh image rendering' })

vim.api.nvim_create_user_command('NvpicClear', function()
  require('nvpic').clear()
end, { desc = 'Clear all images' })

vim.api.nvim_create_user_command('NvpicInfo', function()
  require('nvpic').info()
end, { desc = 'Show nvpic info' })
