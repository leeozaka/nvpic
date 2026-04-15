local cache = require('nvpic.cache')
local config = require('nvpic.config')

describe('nvpic.cache', function()
  local test_dir
  local original_sha256

  before_each(function()
    test_dir = vim.fn.tempname()
    vim.fn.mkdir(test_dir, 'p')
    config.reset()
    config.setup({ pics_dir = 'pics' })
    cache.set_root(test_dir)
    original_sha256 = vim.fn.sha256
  end)

  after_each(function()
    vim.fn.sha256 = original_sha256
    vim.fn.delete(test_dir, 'rf')
  end)

  describe('store', function()
    it('stores image data and returns relative path', function()
      local data = 'fake_png_data_1234567890'
      local path = cache.store(data, 'clipboard')
      assert.is_not_nil(path)
      assert.truthy(path:match('^pics/[a-f0-9]+%.png$'))
    end)

    it('creates pics directory if it does not exist', function()
      local pics_path = test_dir .. '/pics'
      assert.equals(0, vim.fn.isdirectory(pics_path))
      cache.store('some_data', 'clipboard')
      assert.equals(1, vim.fn.isdirectory(pics_path))
    end)

    it('deduplicates identical data', function()
      local path1 = cache.store('identical_data', 'clipboard')
      local path2 = cache.store('identical_data', 'clipboard')
      assert.equals(path1, path2)
    end)

    it('produces different paths for different data', function()
      local path1 = cache.store('data_one', 'clipboard')
      local path2 = cache.store('data_two', 'clipboard')
      assert.is_not.equals(path1, path2)
    end)

    it('stores binary data with null bytes', function()
      local data = 'png\0binary\255payload'
      local path = cache.store(data, 'clipboard')
      local abs = cache.resolve(path)
      local stored = vim.fn.readblob(abs)
      assert.equals(data, stored)
    end)

    it('keeps extending the hash until a collision is resolved', function()
      local pics_path = test_dir .. '/pics'
      vim.fn.mkdir(pics_path, 'p')
      vim.fn.writefile({ 'existing-6' }, pics_path .. '/aaaaaa.png')
      vim.fn.writefile({ 'existing-8' }, pics_path .. '/aaaaaaaa.png')
      vim.fn.writefile({ 'existing-10' }, pics_path .. '/aaaaaaaaaa.png')
      vim.fn.writefile({ 'existing-12' }, pics_path .. '/aaaaaaaaaaaa.png')

      local encoded_second = vim.base64.encode('second')
      vim.fn.sha256 = function(data)
        if data == encoded_second then
          return 'aaaaaaaaaaaa22bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
        end

        return original_sha256(data)
      end

      local path2 = cache.store('second', 'clipboard')

      assert.equals('pics/aaaaaaaaaaaa22.png', path2)
      assert.equals('existing-12\n', vim.fn.readblob(pics_path .. '/aaaaaaaaaaaa.png'))
      assert.equals('second', vim.fn.readblob(cache.resolve(path2)))
    end)
  end)

  describe('resolve', function()
    it('resolves relative path to absolute', function()
      local rel = cache.store('test_data', 'clipboard')
      local abs = cache.resolve(rel)
      assert.is_not_nil(abs:find(test_dir, 1, true))
      assert.equals(1, vim.fn.filereadable(abs))
    end)

    it('rejects paths outside the configured pics_dir', function()
      assert.is_nil(cache.resolve('../secret.png'))
      assert.is_nil(cache.resolve('other/secret.png'))
      assert.is_nil(cache.resolve('/tmp/secret.png'))
    end)
  end)

  describe('exists', function()
    it('returns true for stored images', function()
      local path = cache.store('test_data', 'clipboard')
      assert.is_true(cache.exists(path))
    end)

    it('returns false for missing images', function()
      assert.is_false(cache.exists('pics/nonexistent.png'))
    end)
  end)

  describe('list', function()
    it('lists all stored images', function()
      cache.store('data_a', 'clipboard')
      cache.store('data_b', 'clipboard')
      local entries = cache.list()
      assert.equals(2, #entries)
    end)

    it('returns empty list when no images', function()
      local entries = cache.list()
      assert.equals(0, #entries)
    end)
  end)

  describe('manifest', function()
    it('writes manifest entry on store', function()
      cache.store('data_abc', 'clipboard')
      local manifest_path = test_dir .. '/pics/manifest.json'
      assert.equals(1, vim.fn.filereadable(manifest_path))
      local content = vim.fn.readfile(manifest_path)
      local manifest = vim.json.decode(table.concat(content, '\n'))
      local key = next(manifest)
      assert.equals('clipboard', manifest[key].source)
      assert.is_not_nil(manifest[key].created)
    end)

    it('extracts width and height from a valid PNG', function()
      -- Minimal valid PNG: 8-byte sig + IHDR chunk (13 bytes data)
      -- Width=2, Height=3 encoded as big-endian u32 at offsets 16-23
      local sig = '\137PNG\r\n\26\n'
      local ihdr_len = '\0\0\0\13' -- 13 bytes
      local ihdr_type = 'IHDR'
      local width = '\0\0\0\2'   -- 2
      local height = '\0\0\0\3'  -- 3
      local rest = '\8\2\0\0\0'  -- bit depth, color type, compression, filter, interlace
      local crc = '\0\0\0\0'     -- fake CRC (not validated here)
      local png = sig .. ihdr_len .. ihdr_type .. width .. height .. rest .. crc

      local path = cache.store(png, 'test')
      local manifest_path = test_dir .. '/pics/manifest.json'
      local content = vim.fn.readfile(manifest_path)
      local manifest = vim.json.decode(table.concat(content, '\n'))
      local key = vim.fn.fnamemodify(path, ':t')
      assert.equals(2, manifest[key].width)
      assert.equals(3, manifest[key].height)
    end)

    it('stores nil dimensions for non-PNG data', function()
      cache.store('not_a_png', 'clipboard')
      local manifest_path = test_dir .. '/pics/manifest.json'
      local content = vim.fn.readfile(manifest_path)
      local manifest = vim.json.decode(table.concat(content, '\n'))
      local key = next(manifest)
      assert.is_nil(manifest[key].width)
      assert.is_nil(manifest[key].height)
    end)

    it('warns on corrupt manifest and returns empty table', function()
      local pics_path = test_dir .. '/pics'
      vim.fn.mkdir(pics_path, 'p')
      vim.fn.writefile({ 'not json at all {{{' }, pics_path .. '/manifest.json')

      local notified = false
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        if msg:match('corrupt') and level == vim.log.levels.WARN then
          notified = true
        end
      end

      cache.store('some_data', 'clipboard')

      vim.notify = orig_notify
      assert.is_true(notified)
    end)
  end)
end)
