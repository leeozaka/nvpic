local config = require('nvpic.config')
local renderer = require('nvpic.renderer')
local protocol = require('nvpic.protocol')
local cache = require('nvpic.cache')

local M = {}

local augroup = vim.api.nvim_create_augroup('nvpic', { clear = true })

---@param bufnr? number
local function find_root(bufnr)
  bufnr = bufnr or 0
  local name = vim.api.nvim_buf_get_name(bufnr)
  local root = nil
  if name ~= '' then
    root = vim.fs.root(name, { '.git', '.nvpic' })
  end
  if not root and bufnr == 0 then
    root = vim.fs.root(0, { '.git', '.nvpic' })
  end
  return root or vim.fn.getcwd()
end

---@param bufnr? number
local function sync_root(bufnr)
  cache.set_root(find_root(bufnr))
end

---@param bufnr number
---@return boolean
local function buffer_is_visible(bufnr)
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr then
      return true
    end
  end
  return false
end

---@return integer[]
local function scrolled_windows()
  local wins = {}
  local seen = {}
  for key, _ in pairs(vim.v.event or {}) do
    if key ~= 'all' then
      local winid = tonumber(key)
      if winid and not seen[winid] then
        seen[winid] = true
        table.insert(wins, winid)
      end
    end
  end
  return wins
end

---@param preferred_wins? integer[]
local function refresh_visible_active_buffers(preferred_wins)
  local ordered = {}
  local seen = {}

  local function add(winid)
    if not winid or not vim.api.nvim_win_is_valid(winid) then
      return
    end
    local bufnr = vim.api.nvim_win_get_buf(winid)
    if seen[bufnr] or not renderer.is_active(bufnr) then
      return
    end
    seen[bufnr] = true
    table.insert(ordered, { bufnr = bufnr, winid = winid })
  end

  for _, winid in ipairs(preferred_wins or {}) do
    add(winid)
  end
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    add(winid)
  end

  for _, item in ipairs(ordered) do
    sync_root(item.bufnr)
    renderer.render_all(item.bufnr, item.winid)
  end
end

---@param opts? table
function M.setup(opts)
  config.setup(opts)
  local cfg = config.get()

  sync_root()
  vim.api.nvim_clear_autocmds({ group = augroup })

  if cfg.protocol then
    local proto = protocol.set(cfg.protocol)
    if not proto then
      vim.notify('nvpic: protocol "' .. cfg.protocol .. '" not found', vim.log.levels.WARN)
    end
  else
    local proto = protocol.detect()
    if not proto then
      vim.notify('nvpic: no supported image protocol detected', vim.log.levels.WARN)
    end
  end

  if cfg.keymaps.paste then
    vim.keymap.set('n', cfg.keymaps.paste, function()
      M.paste()
    end, { desc = 'nvpic: paste image' })
  end
  if cfg.keymaps.pick then
    vim.keymap.set('n', cfg.keymaps.pick, function()
      M.pick()
    end, { desc = 'nvpic: pick image' })
  end
  if cfg.keymaps.toggle then
    vim.keymap.set('n', cfg.keymaps.toggle, function()
      M.toggle()
    end, { desc = 'nvpic: toggle images' })
  end
  if cfg.keymaps.refresh then
    vim.keymap.set('n', cfg.keymaps.refresh, function()
      M.refresh()
    end, { desc = 'nvpic: refresh images' })
  end

  if cfg.auto_render then
    vim.api.nvim_create_autocmd({ 'BufRead', 'BufEnter', 'WinEnter' }, {
      group = augroup,
      callback = function(ev)
        sync_root(ev.buf)
        local winid = vim.api.nvim_get_current_win()
        if not vim.api.nvim_win_is_valid(winid) or vim.api.nvim_win_get_buf(winid) ~= ev.buf then
          winid = nil
        end
        renderer.render_all(ev.buf, winid)
      end,
      desc = 'nvpic: auto-render images',
    })
  end

  vim.api.nvim_create_autocmd('BufLeave', {
    group = augroup,
    callback = function(ev)
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(ev.buf) and not buffer_is_visible(ev.buf) then
          renderer.clear(ev.buf)
        end
      end)
    end,
    desc = 'nvpic: clear images on leave',
  })

  vim.api.nvim_create_autocmd('BufDelete', {
    group = augroup,
    callback = function(ev)
      renderer.clear(ev.buf)
    end,
    desc = 'nvpic: clear images on delete',
  })

  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    group = augroup,
    callback = function(ev)
      local should_rescan = renderer.is_active(ev.buf)
      if not should_rescan and type(renderer.has_blocks) == 'function' then
        should_rescan = renderer.has_blocks(ev.buf)
      end
      if should_rescan then
        local winid = vim.api.nvim_get_current_win()
        if not vim.api.nvim_win_is_valid(winid) or vim.api.nvim_win_get_buf(winid) ~= ev.buf then
          winid = nil
        end
        renderer.schedule_rescan(ev.buf, winid)
      end
    end,
    desc = 'nvpic: debounced re-scan on edit',
  })

  vim.api.nvim_create_autocmd({ 'VimResized', 'WinResized', 'WinScrolled' }, {
    group = augroup,
    callback = function()
      local wins = scrolled_windows()
      refresh_visible_active_buffers(#wins > 0 and wins or nil)
    end,
    desc = 'nvpic: refresh images on window changes',
  })

  vim.api.nvim_create_autocmd('OptionSet', {
    group = augroup,
    pattern = { 'wrap', 'number', 'relativenumber', 'signcolumn', 'foldcolumn' },
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      if renderer.is_active(bufnr) then
        sync_root(bufnr)
        renderer.render_all(bufnr, vim.api.nvim_get_current_win())
      end
    end,
    desc = 'nvpic: refresh images on layout option changes',
  })

  if cfg.telescope then
    pcall(function()
      require('nvpic.integrations.telescope').setup()
    end)
  end
end

function M.paste()
  sync_root()
  require('nvpic.ui.float').open()
end

function M.pick()
  sync_root()
  local cfg = config.get()
  if cfg.telescope then
    local ok = pcall(function()
      require('telescope').extensions.nvpic.pick()
    end)
    if ok then
      return
    end
  end
  require('nvpic.ui.picker').open()
end

---@param bufnr? number
function M.toggle(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  sync_root()
  renderer.toggle(bufnr)
end

---@param bufnr? number
function M.refresh(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  sync_root(bufnr)
  local winid = nil
  if bufnr == vim.api.nvim_get_current_buf() then
    winid = vim.api.nvim_get_current_win()
  end
  renderer.render_all(bufnr, winid)
end

---@param bufnr? number
function M.clear(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  renderer.clear(bufnr)
end

---@param bufnr? number
---@return boolean
function M.is_active(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return renderer.is_active(bufnr)
end

---@return string|nil
function M.get_protocol()
  local proto = protocol.get_active()
  return proto and proto.name or nil
end

function M.info()
  sync_root()
  local cfg = config.get()
  local proto = protocol.get_active()
  local entries = cache.list()
  local lines = {
    'nvpic info:',
    '  Protocol: ' .. (proto and proto.name or 'none'),
    '  Pics dir: ' .. cfg.pics_dir,
    '  Images:   ' .. tostring(#entries),
    '  Auto-render: ' .. tostring(cfg.auto_render),
    '  Telescope: ' .. tostring(cfg.telescope),
  }
  vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO)
end

return M
