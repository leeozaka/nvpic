local root = vim.fn.fnamemodify(vim.fn.expand('<sfile>:p'), ':h:h')
vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:prepend(vim.fn.stdpath('data') .. '/lazy/plenary.nvim')
vim.cmd('runtime plugin/plenary.vim')
