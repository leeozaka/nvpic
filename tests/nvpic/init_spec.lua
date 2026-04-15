describe('nvpic (init)', function()
  local orig_notify
  local orig_term
  local notify_calls
  local orig_float
  local orig_picker
  local orig_renderer
  local orig_telescope

  local function unload_nvpic()
    local names = {}
    for name, _ in pairs(package.loaded) do
      if name == 'nvpic' or (type(name) == 'string' and name:sub(1, 6) == 'nvpic.') then
        table.insert(names, name)
      end
    end
    for _, name in ipairs(names) do
      package.loaded[name] = nil
    end
  end

  local function reload_protocol_clean()
    package.loaded['nvpic.protocol'] = nil
    package.loaded['nvpic.protocol.kitty'] = nil
    return require('nvpic.protocol')
  end

  before_each(function()
    notify_calls = {}
    orig_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(notify_calls, { msg = msg, level = level })
    end
    orig_term = vim.env.TERM_PROGRAM
    orig_float = package.loaded['nvpic.ui.float']
    orig_picker = package.loaded['nvpic.ui.picker']
    orig_renderer = package.loaded['nvpic.renderer']
    orig_telescope = package.loaded['telescope']
    require('nvpic.config').reset()
  end)

  after_each(function()
    vim.notify = orig_notify
    vim.env.TERM_PROGRAM = orig_term
    package.loaded['nvpic.ui.float'] = orig_float
    package.loaded['nvpic.ui.picker'] = orig_picker
    package.loaded['nvpic.renderer'] = orig_renderer
    package.loaded['telescope'] = orig_telescope
    unload_nvpic()
    reload_protocol_clean()
    require('nvpic.config').reset()
  end)

  it('setup() sets cache root from find_root()', function()
    local base = vim.fn.getcwd()
    local proj = base .. '/_nvpic_init_spec_root'
    vim.fn.mkdir(proj .. '/.git', 'p')
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, proj .. '/file.lua')
    local prev_buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_set_current_buf(buf)
    local ok, err = pcall(function()
      unload_nvpic()
      local nvpic = require('nvpic')
      nvpic.setup({ protocol = 'kitty' })
      local resolved = require('nvpic.cache').resolve('pics/x.png')
      assert.equals(proj .. '/pics/x.png', resolved)
    end)
    if vim.api.nvim_buf_is_valid(prev_buf) then
      vim.api.nvim_set_current_buf(prev_buf)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
    vim.fn.delete(proj, 'rf')
    if not ok then
      error(err)
    end
  end)

  it('pick() refreshes cache root from the current buffer project', function()
    local base = vim.fn.getcwd()
    local proj = base .. '/_nvpic_init_pick_root'
    vim.fn.mkdir(proj .. '/.git', 'p')
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, proj .. '/file.lua')
    local prev_buf = vim.api.nvim_get_current_buf()
    local picker_calls = 0
    local ok, err = pcall(function()
      unload_nvpic()
      package.loaded['nvpic.ui.picker'] = {
        open = function()
          picker_calls = picker_calls + 1
        end,
      }
      local nvpic = require('nvpic')
      nvpic.setup({ protocol = 'kitty' })
      vim.api.nvim_set_current_buf(buf)
      nvpic.pick()
      assert.equals(1, picker_calls)
      assert.equals(proj .. '/pics/x.png', require('nvpic.cache').resolve('pics/x.png'))
    end)
    if vim.api.nvim_buf_is_valid(prev_buf) then
      vim.api.nvim_set_current_buf(prev_buf)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
    vim.fn.delete(proj, 'rf')
    if not ok then
      error(err)
    end
  end)

  it('setup() warns when forced protocol is not found', function()
    unload_nvpic()
    local nvpic = require('nvpic')
    nvpic.setup({ protocol = 'definitely_missing_protocol' })
    assert.equals(1, #notify_calls)
    assert.equals(vim.log.levels.WARN, notify_calls[1].level)
    assert.truthy(notify_calls[1].msg:match('not found'))
  end)

  it('setup() warns on auto-detect when no protocol is detected', function()
    vim.env.TERM_PROGRAM = ''
    reload_protocol_clean()
    unload_nvpic()
    local nvpic = require('nvpic')
    nvpic.setup({})
    local warned = false
    for _, c in ipairs(notify_calls) do
      if type(c.msg) == 'string' and c.msg:match('no supported image protocol') then
        warned = true
        assert.equals(vim.log.levels.WARN, c.level)
      end
    end
    assert.is_true(warned)
  end)

  it('setup() does not duplicate autocommands on repeated calls', function()
    unload_nvpic()
    local nvpic = require('nvpic')
    nvpic.setup({ protocol = 'kitty' })
    local first = vim.api.nvim_get_autocmds({ group = 'nvpic' })

    nvpic.setup({ protocol = 'kitty' })
    local second = vim.api.nvim_get_autocmds({ group = 'nvpic' })

    assert.equals(#first, #second)
  end)

  it('re-renders active buffers on window entry and geometry changes', function()
    local calls = {}
    unload_nvpic()
    package.loaded['nvpic.renderer'] = {
      toggle = function() end,
      render_all = function(bufnr, winid)
        table.insert(calls, { bufnr = bufnr, winid = winid })
      end,
      clear = function() end,
      is_active = function(bufnr)
        return bufnr == vim.api.nvim_get_current_buf()
      end,
    }
    local nvpic = require('nvpic')
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    nvpic.setup({ protocol = 'kitty' })
    local current_win = vim.api.nvim_get_current_win()

    vim.api.nvim_exec_autocmds('WinEnter', { buffer = buf })
    vim.api.nvim_exec_autocmds('VimResized', {})
    vim.api.nvim_exec_autocmds('WinResized', {})
    vim.api.nvim_exec_autocmds('WinScrolled', {})

    assert.same({
      { bufnr = buf, winid = current_win },
      { bufnr = buf, winid = current_win },
      { bufnr = buf, winid = current_win },
      { bufnr = buf, winid = current_win },
    }, calls)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it('passes the triggering window to renderer.schedule_rescan on edits', function()
    local calls = {}
    unload_nvpic()
    package.loaded['nvpic.renderer'] = {
      toggle = function() end,
      render_all = function() end,
      clear = function() end,
      is_active = function(bufnr)
        return bufnr == vim.api.nvim_get_current_buf()
      end,
      has_blocks = function()
        return false
      end,
      schedule_rescan = function(bufnr, winid)
        table.insert(calls, { bufnr = bufnr, winid = winid })
      end,
    }
    local nvpic = require('nvpic')
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    nvpic.setup({ protocol = 'kitty' })
    local current_win = vim.api.nvim_get_current_win()

    vim.api.nvim_exec_autocmds('TextChanged', { buffer = buf })

    assert.same({
      { bufnr = buf, winid = current_win },
    }, calls)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it('schedules rescans when edits reintroduce pic blocks in an inactive buffer', function()
    local calls = {}
    unload_nvpic()
    package.loaded['nvpic.renderer'] = {
      toggle = function() end,
      render_all = function() end,
      clear = function() end,
      is_active = function()
        return false
      end,
      has_blocks = function(bufnr)
        return bufnr == vim.api.nvim_get_current_buf()
      end,
      schedule_rescan = function(bufnr, winid)
        table.insert(calls, { bufnr = bufnr, winid = winid })
      end,
    }
    local nvpic = require('nvpic')
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    nvpic.setup({ protocol = 'kitty' })
    local current_win = vim.api.nvim_get_current_win()

    vim.api.nvim_exec_autocmds('TextChanged', { buffer = buf })

    assert.same({
      { bufnr = buf, winid = current_win },
    }, calls)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it('does not clear a buffer that remains visible in another window', function()
    local cleared = {}
    unload_nvpic()
    package.loaded['nvpic.renderer'] = {
      toggle = function() end,
      render_all = function() end,
      clear = function(bufnr)
        table.insert(cleared, bufnr)
      end,
      is_active = function()
        return true
      end,
      has_blocks = function()
        return false
      end,
      schedule_rescan = function() end,
    }
    local nvpic = require('nvpic')
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    nvpic.setup({ protocol = 'kitty', auto_render = false })

    local first_win = vim.api.nvim_get_current_win()
    vim.cmd('split')
    local second_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(first_win, buf)
    vim.api.nvim_win_set_buf(second_win, buf)

    vim.api.nvim_exec_autocmds('BufLeave', { buffer = buf })

    assert.same({}, cleared)
    vim.cmd('only')
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it('paste() delegates to ui.float.open', function()
    local calls = 0
    unload_nvpic()
    package.loaded['nvpic.ui.float'] = {
      open = function()
        calls = calls + 1
      end,
    }
    local nvpic = require('nvpic')
    nvpic.paste()
    assert.equals(1, calls)
  end)

  it('toggle(), refresh(), clear(), is_active() delegate to renderer', function()
    local calls = { toggle = {}, refresh = {}, clear = {}, is_active = {} }
    unload_nvpic()
    package.loaded['nvpic.renderer'] = {
      toggle = function(bufnr)
        table.insert(calls.toggle, bufnr)
      end,
      render_all = function(bufnr)
        table.insert(calls.refresh, bufnr)
      end,
      clear = function(bufnr)
        table.insert(calls.clear, bufnr)
      end,
      is_active = function(bufnr)
        table.insert(calls.is_active, bufnr)
        return bufnr == 42
      end,
    }
    local nvpic = require('nvpic')
    local buf = vim.api.nvim_create_buf(false, true)
    nvpic.toggle(buf)
    nvpic.refresh(buf)
    nvpic.clear(buf)
    assert.is_true(nvpic.is_active(42))
    assert.is_false(nvpic.is_active(7))
    assert.same({ buf }, calls.toggle)
    assert.same({ buf }, calls.refresh)
    assert.same({ buf }, calls.clear)
    assert.same({ 42, 7 }, calls.is_active)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it('pick() falls back to built-in picker when telescope call fails', function()
    local picker_calls = 0
    unload_nvpic()
    package.loaded['nvpic.ui.picker'] = {
      open = function()
        picker_calls = picker_calls + 1
      end,
    }
    package.loaded['telescope'] = {
      extensions = {
        nvpic = {
          pick = function()
            error('telescope pick failed')
          end,
        },
      },
    }
    require('nvpic.config').setup({ telescope = true })
    local nvpic = require('nvpic')
    nvpic.pick()
    assert.equals(1, picker_calls)
  end)

  it('info() notifies a summary', function()
    unload_nvpic()
    local nvpic = require('nvpic')
    nvpic.info()
    assert.is_true(#notify_calls >= 1)
    local msg = notify_calls[#notify_calls].msg
    assert.equals(vim.log.levels.INFO, notify_calls[#notify_calls].level)
    assert.truthy(msg:match('nvpic info'))
    assert.truthy(msg:match('Protocol'))
    assert.truthy(msg:match('Pics dir'))
    assert.truthy(msg:match('Images'))
  end)

  it('get_protocol() returns active protocol name when set', function()
    unload_nvpic()
    require('nvpic').setup({ protocol = 'kitty' })
    assert.equals('kitty', require('nvpic').get_protocol())
  end)
end)

describe('nvpic plugin entry', function()
  local plugin_path = vim.fn.getcwd() .. '/plugin/nvpic.lua'

  before_each(function()
    vim.g.loaded_nvpic = nil
    local names = {}
    for name, _ in pairs(package.loaded) do
      if name == 'nvpic' or (type(name) == 'string' and name:sub(1, 6) == 'nvpic.') then
        table.insert(names, name)
      end
    end
    for _, name in ipairs(names) do
      package.loaded[name] = nil
    end
    require('nvpic.config').reset()
  end)

  it('sources once: second load does not re-register due to loaded guard', function()
    local created = 0
    local orig = vim.api.nvim_create_user_command
    vim.api.nvim_create_user_command = function(name, rhs, opts)
      created = created + 1
      return orig(name, rhs, opts)
    end
    assert.equals(1, vim.fn.filereadable(plugin_path))
    dofile(plugin_path)
    local after_first = created
    dofile(plugin_path)
    vim.api.nvim_create_user_command = orig
    assert.is_true(after_first >= 6)
    assert.equals(after_first, created)
  end)

  it('defines expected user commands', function()
    vim.g.loaded_nvpic = nil
    dofile(plugin_path)
    local cmds = vim.api.nvim_get_commands({})
    for _, name in ipairs({
      'NvpicPaste',
      'NvpicPick',
      'NvpicToggle',
      'NvpicRefresh',
      'NvpicClear',
      'NvpicInfo',
    }) do
      assert.is_not_nil(cmds[name], 'missing command ' .. name)
    end
  end)
end)
