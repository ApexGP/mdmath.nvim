-- Lists mdmath marks whose screen cells overlap. Run it while the duplicated /
-- overlapping formula is visible:
--
--   :luafile tests/manual/overlaps.lua
--
-- Two overlapping marks are a plugin bug; a single mark with a duplicated image
-- is a terminal-side leftover (the placeholder id keeps an old placement).

local ns = vim.api.nvim_get_namespaces()['mdmath-marks']
assert(ns, 'mdmath-marks namespace not found: is the plugin enabled?')

local buf = vim.api.nvim_get_current_buf()
local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {details = true})

---@param chunks table
---@return integer
local function width(chunks)
    local out = 0
    for _, chunk in ipairs(chunks) do
        out = out + vim.fn.strdisplaywidth(chunk[1])
    end
    return out
end

local rects = {}
for _, mark in ipairs(marks) do
    local id, row, col, details = mark[1], mark[2], mark[3], mark[4] or {}
    rects[#rects + 1] = {
        id = id,
        row = row,
        col = col,
        width = details.virt_text and width(details.virt_text) or 0,
        height = details.virt_lines and (1 + #details.virt_lines) or 1,
        color = tostring(details.hl_group),
        eol = details.virt_text_pos == 'eol',
    }
end

local found = 0
for i = 1, #rects do
    for j = i + 1, #rects do
        local a, b = rects[i], rects[j]
        local same_rows = a.row < b.row + b.height and b.row < a.row + a.height
        local a0, a1 = a.col, a.col + math.max(a.width, 1)
        local b0, b1 = b.col, b.col + math.max(b.width, 1)
        local same_cells = a.row ~= b.row or (a0 < b1 and b0 < a1)
        if same_rows and same_cells then
            found = found + 1
            print(string.format(
                'overlap: mark %d (row %d col %d w %d h %d %s%s) <> mark %d (row %d col %d w %d h %d %s%s)',
                a.id, a.row, a.col, a.width, a.height, a.color, a.eol and ' eol' or '',
                b.id, b.row, b.col, b.width, b.height, b.color, b.eol and ' eol' or ''))
        end
    end
end

print(('marks=%d overlapping pairs=%d'):format(#rects, found))
