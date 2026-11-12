-- Lists mdmath marks whose *cells* overlap. Run it while the duplicated /
-- overlapping formula is visible:
--
--   :luafile tests/manual/overlaps.lua
--
-- `virt_lines` are screen rows below (or above) the extmark row, not on it, so
-- an image taller than its source block correctly produces two extmarks on the
-- same row. Only real cell collisions are reported.
--
-- Two overlapping marks are a plugin bug; a single mark whose placeholder colour
-- (the image id, e.g. #F00000 red) is visible without an image is a terminal
-- leftover, not a duplicate.

local ns = vim.api.nvim_get_namespaces()['mdmath-marks']
assert(ns, 'mdmath-marks namespace not found: is the plugin enabled?')

local buf = vim.api.nvim_get_current_buf()
local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {details = true})

---@param chunks table|nil
---@return integer
local function width(chunks)
    if not chunks then
        return 0
    end
    local out = 0
    for _, chunk in ipairs(chunks) do
        out = out + vim.fn.strdisplaywidth(chunk[1])
    end
    return out
end

---@param chunks table|nil
---@return string
local function color(chunks)
    local chunk = chunks and chunks[1]
    return chunk and tostring(chunk[2]) or 'nil'
end

---@param text string
---@return string
local function preview(text)
    local out = text:gsub('\u{10EEEE}', 'P')
    return '"' .. out:sub(1, 16) .. (#out > 16 and '...' or '') .. '"'
end

local rects = {}
for _, mark in ipairs(marks) do
    local id, row, col, details = mark[1], mark[2], mark[3], mark[4] or {}

    if details.virt_text then
        local first = details.virt_text[1]
        local text = ''
        if first and first[1] then
            text = first[1]
        end
        -- `eol` text is drawn at the end of the line, not at the extmark column.
        local start_col = col
        if details.virt_text_pos == 'eol' then
            local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ''
            start_col = vim.fn.strdisplaywidth(line)
        end
        rects[#rects + 1] = {
            id = id,
            row = row,
            col = start_col,
            width = width(details.virt_text),
            height = 1,
            color = color(details.virt_text),
            text = preview(text),
            eol = details.virt_text_pos == 'eol',
        }
    end

    if details.virt_lines and #details.virt_lines > 0 then
        local lines = details.virt_lines or {}
        local start = details.virt_lines_above and (row - #lines) or (row + 1)
        local line_width = 0
        for _, line in ipairs(lines) do
            line_width = math.max(line_width, width(line))
        end
        local first_line = lines[1]
        local first_chunk = first_line and first_line[1]
        local text = ''
        if first_chunk and first_chunk[1] then
            text = first_chunk[1]
        end
        rects[#rects + 1] = {
            id = id,
            row = start,
            col = 0,
            width = line_width,
            height = #lines,
            color = color(first_line),
            text = preview(text),
        }
    end
end

local found = 0
for i = 1, #rects do
    for j = i + 1, #rects do
        local a, b = rects[i], rects[j]
        local rows = a.row < b.row + b.height and b.row < a.row + a.height
        local a1 = a.col + math.max(a.width, 1)
        local b1 = b.col + math.max(b.width, 1)
        local cols = a.row ~= b.row or (a.col < b1 and b.col < a1)
        if rows and cols then
            found = found + 1
            print(string.format(
                'overlap: mark %d row=%d col=%d w=%d h=%d %s%s %s <> mark %d row=%d col=%d w=%d h=%d %s%s %s',
                a.id, a.row, a.col, a.width, a.height, a.color, a.eol and ' eol' or '', a.text,
                b.id, b.row, b.col, b.width, b.height, b.color, b.eol and ' eol' or '', b.text))
        end
    end
end

print(('marks=%d rects=%d overlapping pairs=%d'):format(#marks, #rects, found))
