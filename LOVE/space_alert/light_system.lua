-- light_system.lua
local LightSystem = {}

LightSystem.MAX_LEVEL = 10
LightSystem.SKY_LEVEL = 8
LightSystem.PLAYER_LEVEL = 10

function LightSystem.new()
    return {
        enabled = true,
    }
end

local function computeLight(ast, playerX, playerY, tileSize)
    local gw, gh = ast.gridW, ast.gridH
    local total = gw * gh
    local tiles = ast.tiles

    if ast.lightLevel == nil or #ast.lightLevel ~= total then
        ast.lightLevel = {}
        for i = 1, total do
            ast.lightLevel[i] = 0
        end
    end
    local level = ast.lightLevel

    for i = 1, total do
        level[i] = -1
    end

    local queue = {}
    local qHead = 1
    local qTail = 0

    local function push(idx)
        qTail = qTail + 1
        queue[qTail] = idx
    end

    local function trySet(idx, val)
        if val > level[idx] then
            level[idx] = val
            push(idx)
        end
    end

    local function isSolid(lx, ly)
        if lx < 0 or ly < 0 or lx >= gw or ly >= gh then
            return false
        end
        return tiles[ly * gw + lx + 1] ~= nil
    end

    for ly = 0, gh - 1 do
        for lx = 0, gw - 1 do
            local idx = ly * gw + lx + 1
            if tiles[idx] then
                local exposed = false
                for dy = -1, 1 do
                    for dx = -1, 1 do
                        if not (dx == 0 and dy == 0) then
                            if not isSolid(lx + dx, ly + dy) then
                                exposed = true
                                break
                            end
                        end
                    end
                    if exposed then break end
                end
                if exposed then
                    trySet(idx, LightSystem.SKY_LEVEL - 2)
                end
            end
        end
    end

    if playerX and playerY then
        local dx = playerX - ast.cx
        local dy = playerY - ast.cy
        local ca, sa = math.cos(-(ast.angle or 0)), math.sin(-(ast.angle or 0))
        local plx = dx * ca - dy * sa
        local ply = dx * sa + dy * ca
        local tpx = math.floor(plx / tileSize + gw * 0.5)
        local tpy = math.floor(ply / tileSize + gh * 0.5)
        if tpx >= 0 and tpy >= 0 and tpx < gw and tpy < gh then
            local pidx = tpy * gw + tpx + 1
            trySet(pidx, LightSystem.PLAYER_LEVEL)
        end
    end

    while qHead <= qTail do
        local idx = queue[qHead]
        qHead = qHead + 1

        local cur = level[idx]
        if cur > 1 then
            local ly = math.floor((idx - 1) / gw)
            local lx = (idx - 1) % gw

            local function try(nidx)
                local drop = 1
                local cand = cur - drop
                if cand > level[nidx] then
                    level[nidx] = cand
                    if cand > 1 then
                        push(nidx)
                    end
                end
            end

            if lx > 0 then try(idx - 1) end
            if lx < gw - 1 then try(idx + 1) end
            if ly > 0 then try(idx - gw) end
            if ly < gh - 1 then try(idx + gw) end
        end
    end

    for i = 1, total do
        if level[i] < 0 then
            level[i] = 0
        end
    end
end

function LightSystem.update(ls, asteroids, player, tileSize)
    if not ls.enabled then return end
    local px = player and player.x or nil
    local py = player and player.y or nil
    for _, ast in ipairs(asteroids) do
        computeLight(ast, px, py, tileSize)
    end
end

return LightSystem





