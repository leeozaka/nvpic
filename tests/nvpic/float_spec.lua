describe('nvpic.ui.float', function()
  local float
  local orig_notify
  local orig_clipboard
  local orig_cache
  local orig_marker
  local orig_renderer
  local notify_calls
  local target_buf

  local function reload_float()
    package.loaded['nvpic.ui.float'] = nil
    float = require('nvpic.ui.float')
  end

  local function set_clipboard_stub(t)
    package.loaded['nvpic.clipboard'] = t
  end

  local function set_cache_stub(t)
    package.loaded['nvpic.cache'] = t
  end

  local function set_marker_stub(t)
    package.loaded['nvpic.marker'] = t
  end

  local function set_renderer_stub(t)
    package.loaded['nvpic.renderer'] = t
  end

  before_each(function()
    notify_calls = {}
    orig_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(notify_calls, { msg = msg, level = level })
    end

    orig_clipboard = package.loaded['nvpic.clipboard']
    orig_cache = package.loaded['nvpic.cache']
    orig_marker = package.loaded['nvpic.marker']
    orig_renderer = package.loaded['nvpic.renderer']

    target_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(target_buf)
    vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, { 'line1', 'line2' })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    reload_float()
  end)

  after_each(function()
    vim.notify = orig_notify
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      local cfg = vim.api.nvim_win_get_config(w)
      if cfg.relative ~= '' then
        pcall(vim.api.nvim_win_close, w, true)
      end
    end
    package.loaded['nvpic.clipboard'] = orig_clipboard
    package.loaded['nvpic.cache'] = orig_cache
    package.loaded['nvpic.marker'] = orig_marker
    package.loaded['nvpic.renderer'] = orig_renderer
    package.loaded['nvpic.ui.float'] = nil
    if vim.api.nvim_buf_is_valid(target_buf) then
      vim.api.nvim_buf_delete(target_buf, { force = true })
    end
  end)

  it('open() notifies and returns when no image in clipboard', function()
    set_clipboard_stub({
      has_image = function()
        return false
      end,
    })
    reload_float()
    float.open()
    assert.equals(1, #notify_calls)
    assert.equals('nvpic: no image in clipboard', notify_calls[1].msg)
    assert.equals(vim.log.levels.INFO, notify_calls[1].level)
  end)

  it('open() creates a floating window when image exists', function()
    set_clipboard_stub({
      has_image = function()
        return true
      end,
      read_image = function()
        return '', nil
      end,
    })
    reload_float()
    local before = #vim.api.nvim_list_wins()
    float.open()
    assert.equals(before + 1, #vim.api.nvim_list_wins())
    local float_win
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      local cfg = vim.api.nvim_win_get_config(w)
      if cfg.relative ~= '' then
        float_win = w
        break
      end
    end
    assert.is_not_nil(float_win)
    assert.is_true(vim.api.nvim_win_is_valid(float_win))
    assert.is_true(vim.api.nvim_win_get_width(float_win) > 0)
    vim.api.nvim_set_current_win(float_win)
    vim.api.nvim_feedkeys('q', 'nx', false)
  end)

  it('confirming paste reads image, stores it, inserts marker lines, and calls renderer.render_block', function()
    local read_calls = 0
    set_clipboard_stub({
      has_image = function()
        return true
      end,
      read_image = function()
        read_calls = read_calls + 1
        return 'fakepng', nil
      end,
    })
    set_cache_stub({
      store = function(data, source)
        assert.equals('fakepng', data)
        assert.equals('clipboard', source)
        return 'pics/abc.png'
      end,
    })
    local built_pic
    local built_cs
    set_marker_stub({
      build = function(pic, cs)
        built_pic = pic
        built_cs = cs
        return { '// $$pic-start', '// path: pics/abc.png', '// $$pic-end' }
      end,
    })
    local render_calls = {}
    set_renderer_stub({
      render_block = function(bufnr, block)
        table.insert(render_calls, { bufnr = bufnr, block = block })
      end,
    })
    reload_float()

    vim.bo[target_buf].commentstring = '// %s'
    vim.api.nvim_set_current_buf(target_buf)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    float.open()

    local float_win
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      local cfg = vim.api.nvim_win_get_config(w)
      if cfg.relative ~= '' then
        float_win = w
        break
      end
    end
    assert.is_not_nil(float_win)
    local fbuf = vim.api.nvim_win_get_buf(float_win)
    vim.api.nvim_buf_set_lines(fbuf, 0, 2, false, { 'Scale: 0.5', 'Alt:   hello' })
    vim.api.nvim_set_current_win(float_win)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'mtx', false)

    assert.equals(1, read_calls)
    assert.is_not_nil(built_pic)
    assert.equals('pics/abc.png', built_pic.path)
    assert.equals(0.5, built_pic.scale)
    assert.equals('hello', built_pic.alt)
    assert.equals('// %s', built_cs)

    local lines = vim.api.nvim_buf_get_lines(target_buf, 0, -1, false)
    assert.same({ 'line1', '// $$pic-start', '// path: pics/abc.png', '// $$pic-end', 'line2' }, lines)

    assert.equals(1, #render_calls)
    assert.equals(target_buf, render_calls[1].bufnr)
    assert.equals('pics/abc.png', render_calls[1].block.path)
    assert.equals(0.5, render_calls[1].block.scale)
    assert.equals('hello', render_calls[1].block.alt)
    assert.equals(1, render_calls[1].block.start_line)
    assert.equals(3, render_calls[1].block.end_line)
  end)

  it('uses commentstring fallback when buffer commentstring is empty', function()
    set_clipboard_stub({
      has_image = function()
        return true
      end,
      read_image = function()
        return 'x', nil
      end,
    })
    set_cache_stub({
      store = function()
        return 'pics/x.png'
      end,
    })
    local built_cs
    set_marker_stub({
      build = function(_, cs)
        built_cs = cs
        return { '// a', '// b', '// c' }
      end,
    })
    set_renderer_stub({
      render_block = function() end,
    })
    reload_float()
    vim.bo[target_buf].commentstring = ''
    vim.api.nvim_set_current_buf(target_buf)
    float.open()
    local float_win
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      local cfg = vim.api.nvim_win_get_config(w)
      if cfg.relative ~= '' then
        float_win = w
        break
      end
    end
    vim.api.nvim_set_current_win(float_win)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'mtx', false)
    assert.equals('// %s', built_cs)
  end)

  it('cancel closes the float without inserting', function()
    set_clipboard_stub({
      has_image = function()
        return true
      end,
      read_image = function()
        error('read_image should not run on cancel')
      end,
    })
    reload_float()
    float.open()
    local float_win
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      local cfg = vim.api.nvim_win_get_config(w)
      if cfg.relative ~= '' then
        float_win = w
        break
      end
    end
    assert.is_not_nil(float_win)
    vim.api.nvim_set_current_win(float_win)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'mtx', false)
    assert.is_false(vim.api.nvim_win_is_valid(float_win))
    assert.same({ 'line1', 'line2' }, vim.api.nvim_buf_get_lines(target_buf, 0, -1, false))
  end)
end)
