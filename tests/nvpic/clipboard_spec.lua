local uv = vim.uv

local function write_bytes(path, data)
  local fd = assert(uv.fs_open(path, 'w', 420))
  assert(uv.fs_write(fd, data, 0))
  uv.fs_close(fd)
end

local function tbl_to_cmd_str(spec)
  if type(spec) == 'string' then
    return spec
  end
  return table.concat(spec, '\0')
end

describe('nvpic.clipboard', function()
  local clipboard
  local orig_system
  local orig_tempname
  local orig_delete
  local test_base
  local test_png
  local test_tiff

  local function reload_clipboard()
    package.loaded['nvpic.clipboard'] = nil
    clipboard = require('nvpic.clipboard')
  end

  before_each(function()
    reload_clipboard()
    orig_system = vim.system
    orig_tempname = vim.fn.tempname
    orig_delete = vim.fn.delete
    test_base = vim.fn.tempname()
    test_png = test_base .. '.png'
    test_tiff = test_base .. '.tiff'
  end)

  after_each(function()
    vim.system = orig_system
    vim.fn.tempname = orig_tempname
    vim.fn.delete = orig_delete
    pcall(vim.fn.delete, test_png, 'rf')
    pcall(vim.fn.delete, test_tiff, 'rf')
    pcall(vim.fn.delete, test_base, 'rf')
  end)

  describe('has_image', function()
    it('is true when clipboard info mentions public.png', function()
      vim.system = function()
        return {
          wait = function()
            return { code = 0, stdout = 'something public.png here', stderr = '' }
          end,
        }
      end
      assert.is_true(clipboard.has_image())
    end)

    it('is true when clipboard info mentions public.tiff', function()
      vim.system = function()
        return {
          wait = function()
            return { code = 0, stdout = 'public.tiff', stderr = '' }
          end,
        }
      end
      assert.is_true(clipboard.has_image())
    end)

    it('is true when clipboard info mentions TIFF', function()
      vim.system = function()
        return {
          wait = function()
            return { code = 0, stdout = '«class TIFF», 100', stderr = '' }
          end,
        }
      end
      assert.is_true(clipboard.has_image())
    end)

    it('is true when clipboard info mentions PNG', function()
      vim.system = function()
        return {
          wait = function()
            return { code = 0, stdout = '«class PNGf», 200', stderr = '' }
          end,
        }
      end
      assert.is_true(clipboard.has_image())
    end)

    it('is false when clipboard info has no image types', function()
      vim.system = function()
        return {
          wait = function()
            return { code = 0, stdout = '«class utf8», 10', stderr = '' }
          end,
        }
      end
      assert.is_false(clipboard.has_image())
    end)

    it('is false for unrelated lowercase png substrings', function()
      vim.system = function()
        return {
          wait = function()
            return { code = 0, stdout = 'clipboard contains png metadata only', stderr = '' }
          end,
        }
      end
      assert.is_false(clipboard.has_image())
    end)

    it('is false when osascript fails', function()
      vim.system = function()
        return {
          wait = function()
            return { code = 1, stdout = '', stderr = 'err' }
          end,
        }
      end
      assert.is_false(clipboard.has_image())
    end)
  end)

  describe('read_image', function()
    it('returns no-image error when has_image is false', function()
      vim.system = function()
        return {
          wait = function()
            return { code = 0, stdout = 'plain text only', stderr = '' }
          end,
        }
      end
      vim.fn.tempname = function()
        return test_base
      end
      local data, err = clipboard.read_image()
      assert.is_nil(data)
      assert.equals('No image in clipboard', err)
    end)

    it('returns PNG data on successful PNG path', function()
      local png_bytes = '\x89PNG\r\n\0\1binary'
      local calls = {}
      vim.fn.tempname = function()
        return test_base
      end
      vim.system = function(spec)
        table.insert(calls, spec)
        return {
          wait = function()
            local key = tbl_to_cmd_str(spec)
            if key:find('the clipboard info', 1, true) then
              return { code = 0, stdout = '«class PNGf», 99', stderr = '' }
            end
            if key:find('PNGf', 1, true) or key:find('pngBytes', 1, true) then
              write_bytes(test_png, png_bytes)
              return { code = 0, stdout = '', stderr = '' }
            end
            return { code = 99, stdout = '', stderr = 'unexpected' }
          end,
        }
      end
      local data, err = clipboard.read_image()
      assert.is_nil(err)
      assert.equals(png_bytes, data)
      assert.equals(0, vim.fn.filereadable(test_png))
    end)

    it('falls back to TIFF path when PNG export fails', function()
      local png_bytes = '\x89PNG\r\nfallback'
      local calls = {}
      vim.fn.tempname = function()
        return test_base
      end
      vim.system = function(spec)
        table.insert(calls, spec)
        return {
          wait = function()
            local key = tbl_to_cmd_str(spec)
            if key:find('the clipboard info', 1, true) then
              return { code = 0, stdout = '«class TIFF», 10', stderr = '' }
            end
            if key:find('PNGf', 1, true) or (key:find('pngBytes', 1, true)) then
              return { code = 1, stdout = '', stderr = 'no png' }
            end
            if key:find('TIFF', 1, true) and key:find('on run argv', 1, true) then
              write_bytes(test_tiff, 'FAKE')
              return { code = 0, stdout = '', stderr = '' }
            end
            if key:find('sips', 1, true) then
              write_bytes(test_png, png_bytes)
              return { code = 0, stdout = '', stderr = '' }
            end
            return { code = 99, stdout = '', stderr = 'unexpected' }
          end,
        }
      end
      local data, err = clipboard.read_image()
      assert.is_nil(err)
      assert.equals(png_bytes, data)
      assert.equals(0, vim.fn.filereadable(test_png))
      assert.equals(0, vim.fn.filereadable(test_tiff))
    end)

    it('returns failure when both export paths fail', function()
      vim.fn.tempname = function()
        return test_base
      end
      vim.system = function(spec)
        return {
          wait = function()
            local key = tbl_to_cmd_str(spec)
            if key:find('the clipboard info', 1, true) then
              return { code = 0, stdout = '«class PNGf», 1', stderr = '' }
            end
            return { code = 1, stdout = '', stderr = 'fail' }
          end,
        }
      end
      local data, err = clipboard.read_image()
      assert.is_nil(data)
      assert.equals('Failed to read clipboard image', err)
    end)

    it('returns temp-file-not-created when PNG export exits zero but file is missing', function()
      vim.fn.tempname = function()
        return test_base
      end
      vim.system = function(spec)
        return {
          wait = function()
            local key = tbl_to_cmd_str(spec)
            if key:find('the clipboard info', 1, true) then
              return { code = 0, stdout = '«class PNGf», 1', stderr = '' }
            end
            if key:find('PNGf', 1, true) or key:find('pngBytes', 1, true) then
              return { code = 0, stdout = '', stderr = '' }
            end
            return { code = 0, stdout = '', stderr = '' }
          end,
        }
      end
      pcall(vim.fn.delete, test_png, 'rf')
      local data, err = clipboard.read_image()
      assert.is_nil(data)
      assert.equals('Temp file not created', err)
    end)

    it('returns empty-image error when file is empty', function()
      vim.fn.tempname = function()
        return test_base
      end
      vim.system = function(spec)
        return {
          wait = function()
            local key = tbl_to_cmd_str(spec)
            if key:find('the clipboard info', 1, true) then
              return { code = 0, stdout = '«class PNGf», 1', stderr = '' }
            end
            if key:find('PNGf', 1, true) or key:find('pngBytes', 1, true) then
              write_bytes(test_png, '')
              return { code = 0, stdout = '', stderr = '' }
            end
            return { code = 99, stdout = '', stderr = '' }
          end,
        }
      end
      local data, err = clipboard.read_image()
      assert.is_nil(data)
      assert.equals('Clipboard image was empty', err)
    end)
  end)
end)
