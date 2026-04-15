local uv = vim.uv

local M = {}

local CLIPBOARD_INFO = { 'osascript', '-e', 'the clipboard info' }

local PNG_EXPORT = [[on run argv
  set posixPath to item 1 of argv
  set pngBytes to the clipboard as «class PNGf»
  set f to open for access POSIX file posixPath with write permission
  write pngBytes to f
  close access f
end run]]

local TIFF_EXPORT = [[on run argv
  set posixPath to item 1 of argv
  set tiffBytes to the clipboard as «class TIFF»
  set f to open for access POSIX file posixPath with write permission
  write tiffBytes to f
  close access f
end run]]

local function run_cmd(cmd)
  return vim.system(cmd):wait()
end

local function clipboard_info_looks_like_image(info)
  local s = info or ''
  if s:find('public.png', 1, true) then
    return true
  end
  if s:find('public.tiff', 1, true) then
    return true
  end
  if s:find('TIFF', 1, true) then
    return true
  end
  if s:find('PNG', 1, true) then
    return true
  end
  return false
end

function M.has_image()
  local r = run_cmd(CLIPBOARD_INFO)
  if r.code ~= 0 then
    return false
  end
  return clipboard_info_looks_like_image(r.stdout)
end

local function read_binary(path)
  local fd = uv.fs_open(path, 'r', 438)
  if not fd then
    return nil
  end
  local stat = uv.fs_fstat(fd)
  if not stat then
    uv.fs_close(fd)
    return nil
  end
  local data = uv.fs_read(fd, stat.size, 0)
  uv.fs_close(fd)
  return data
end

local function safe_delete(path)
  if path and vim.fn.filereadable(path) == 1 then
    vim.fn.delete(path, 'rf')
  end
end

function M.read_image()
  if not M.has_image() then
    return nil, 'No image in clipboard'
  end

  local base = vim.fn.tempname()
  local png_path = base .. '.png'
  local tiff_path = base .. '.tiff'

  local r_png = run_cmd({ 'osascript', '-e', PNG_EXPORT, png_path })
  if r_png.code == 0 and vim.fn.filereadable(png_path) == 0 then
    return nil, 'Temp file not created'
  end

  if r_png.code ~= 0 or vim.fn.filereadable(png_path) == 0 then
    local r_tiff = run_cmd({ 'osascript', '-e', TIFF_EXPORT, tiff_path })
    if r_tiff.code ~= 0 or vim.fn.filereadable(tiff_path) == 0 then
      safe_delete(tiff_path)
      safe_delete(png_path)
      return nil, 'Failed to read clipboard image'
    end

    local r_sips = run_cmd({ 'sips', '-s', 'format', 'png', tiff_path, '--out', png_path })
    safe_delete(tiff_path)
    if r_sips.code ~= 0 then
      safe_delete(png_path)
      return nil, 'Failed to read clipboard image'
    end
    if vim.fn.filereadable(png_path) == 0 then
      safe_delete(png_path)
      return nil, 'Temp file not created'
    end
  end

  if vim.fn.filereadable(png_path) == 0 then
    safe_delete(png_path)
    return nil, 'Failed to read clipboard image'
  end

  local data = read_binary(png_path)
  safe_delete(png_path)
  if not data then
    return nil, 'Failed to read clipboard image'
  end
  if #data == 0 then
    return nil, 'Clipboard image was empty'
  end

  return data, nil
end

return M
