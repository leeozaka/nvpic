describe('nvpic.ui.picker', function()
  local picker
  local orig_notify
  local orig_ui_select
  local orig_cache
  local orig_marker
  local orig_renderer
  local orig_config
  local notify_calls
  local select_calls
  local target_buf

  local function reload_picker()
    package.loaded['nvpic.ui.picker'] = nil
    picker = require('nvpic.ui.picker')
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
    select_calls = {}
    orig_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(notify_calls, { msg = msg, level = level })
    end

    orig_ui_select = vim.ui.select
    vim.ui.select = function(items, opts, on_choice)
      table.insert(select_calls, { items = items, opts = opts, on_choice = on_choice })
    end

    orig_cache = package.loaded['nvpic.cache']
    orig_marker = package.loaded['nvpic.marker']
    orig_renderer = package.loaded['nvpic.renderer']
    orig_config = package.loaded['nvpic.config']

    local config = require('nvpic.config')
    config.reset()
    config.setup({ pics_dir = 'pics', default_scale = 1.0 })

    target_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(target_buf)
    vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, { 'line1', 'line2' })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    reload_picker()
  end)

  after_each(function()
    vim.notify = orig_notify
    vim.ui.select = orig_ui_select
    package.loaded['nvpic.cache'] = orig_cache
    package.loaded['nvpic.marker'] = orig_marker
    package.loaded['nvpic.renderer'] = orig_renderer
    package.loaded['nvpic.config'] = orig_config
    package.loaded['nvpic.ui.picker'] = nil
    if vim.api.nvim_buf_is_valid(target_buf) then
      vim.api.nvim_buf_delete(target_buf, { force = true })
    end
  end)

  it('open() notifies when cache list is empty', function()
    set_cache_stub({
      list = function()
        return {}
      end,
    })
    reload_picker()
    picker.open()
    assert.equals(1, #notify_calls)
    assert.equals('nvpic: no images in pics', notify_calls[1].msg)
    assert.equals(vim.log.levels.INFO, notify_calls[1].level)
    assert.equals(0, #select_calls)
  end)

  it('open() notifies with configured pics_dir when empty', function()
    require('nvpic.config').setup({ pics_dir = 'assets/img' })
    set_cache_stub({
      list = function()
        return {}
      end,
    })
    reload_picker()
    picker.open()
    assert.equals('nvpic: no images in assets/img', notify_calls[1].msg)
  end)

  it('open() calls vim.ui.select with formatted labels including dimensions when metadata exists', function()
    set_cache_stub({
      list = function()
        return {
          {
            filename = 'a.png',
            path = 'pics/a.png',
            meta = { width = 100, height = 50 },
          },
          {
            filename = 'b.png',
            path = 'pics/b.png',
            meta = {},
          },
        }
      end,
    })
    reload_picker()
    picker.open()
    assert.equals(1, #select_calls)
    assert.equals('nvpic pick> ', select_calls[1].opts.prompt)
    assert.is_function(select_calls[1].opts.format_item)
    assert.equals('x', select_calls[1].opts.format_item('x'))
    local items = select_calls[1].items
    assert.same({ 'a.png (100x50)', 'b.png' }, items)
  end)

  it('selection callback inserts marker lines at cursor and calls renderer.render_block', function()
    set_cache_stub({
      list = function()
        return {
          {
            filename = 'z.png',
            path = 'pics/z.png',
            meta = nil,
          },
        }
      end,
    })
    local built_pic
    local built_cs
    set_marker_stub({
      build = function(pic, cs)
        built_pic = pic
        built_cs = cs
        return { '// $$pic-start', '// path: pics/z.png', '// $$pic-end' }
      end,
    })
    local render_calls = {}
    set_renderer_stub({
      render_block = function(bufnr, block)
        table.insert(render_calls, { bufnr = bufnr, block = block })
      end,
    })
    reload_picker()

    vim.bo[target_buf].commentstring = '// %s'
    vim.api.nvim_set_current_buf(target_buf)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    picker.open()

    assert.equals(1, #select_calls)
    select_calls[1].on_choice('z.png')

    assert.is_not_nil(built_pic)
    assert.equals('pics/z.png', built_pic.path)
    assert.equals(1.0, built_pic.scale)
    assert.equals('', built_pic.alt)
    assert.equals('// %s', built_cs)

    local lines = vim.api.nvim_buf_get_lines(target_buf, 0, -1, false)
    assert.same({ 'line1', '// $$pic-start', '// path: pics/z.png', '// $$pic-end', 'line2' }, lines)

    assert.equals(1, #render_calls)
    assert.equals(target_buf, render_calls[1].bufnr)
    assert.equals('pics/z.png', render_calls[1].block.path)
    assert.equals(1.0, render_calls[1].block.scale)
    assert.equals('', render_calls[1].block.alt)
    assert.equals(1, render_calls[1].block.start_line)
    assert.equals(3, render_calls[1].block.end_line)
  end)

  it('selection callback keeps the original target buffer when focus changes before choice', function()
    local other_buf = vim.api.nvim_create_buf(false, true)
    set_cache_stub({
      list = function()
        return {
          {
            filename = 'z.png',
            path = 'pics/z.png',
            meta = nil,
          },
        }
      end,
    })
    set_marker_stub({
      build = function()
        return { '// $$pic-start', '// path: pics/z.png', '// $$pic-end' }
      end,
    })
    local render_calls = {}
    set_renderer_stub({
      render_block = function(bufnr, block)
        table.insert(render_calls, { bufnr = bufnr, block = block })
      end,
    })
    reload_picker()

    vim.bo[target_buf].commentstring = '// %s'
    vim.api.nvim_set_current_buf(target_buf)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    picker.open()

    vim.api.nvim_set_current_buf(other_buf)
    vim.api.nvim_buf_set_lines(other_buf, 0, -1, false, { 'other' })
    select_calls[1].on_choice('z.png')

    assert.same({ 'line1', '// $$pic-start', '// path: pics/z.png', '// $$pic-end', 'line2' }, vim.api.nvim_buf_get_lines(target_buf, 0, -1, false))
    assert.same({ 'other' }, vim.api.nvim_buf_get_lines(other_buf, 0, -1, false))
    assert.equals(1, #render_calls)
    assert.equals(target_buf, render_calls[1].bufnr)

    vim.api.nvim_buf_delete(other_buf, { force = true })
  end)

  it('uses commentstring fallback when buffer commentstring is empty', function()
    set_cache_stub({
      list = function()
        return {
          { filename = 'q.png', path = 'pics/q.png', meta = nil },
        }
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
    reload_picker()
    vim.bo[target_buf].commentstring = ''
    vim.api.nvim_set_current_buf(target_buf)
    picker.open()
    select_calls[1].on_choice('q.png')
    assert.equals('// %s', built_cs)
  end)

  it('nil selection is a no-op', function()
    set_cache_stub({
      list = function()
        return {
          { filename = 'only.png', path = 'pics/only.png', meta = nil },
        }
      end,
    })
    local render_calls = {}
    set_marker_stub({
      build = function()
        error('marker.build should not run on nil choice')
      end,
    })
    set_renderer_stub({
      render_block = function()
        table.insert(render_calls, {})
      end,
    })
    reload_picker()
    picker.open()
    select_calls[1].on_choice(nil)
    assert.same({ 'line1', 'line2' }, vim.api.nvim_buf_get_lines(target_buf, 0, -1, false))
    assert.equals(0, #render_calls)
  end)
end)
