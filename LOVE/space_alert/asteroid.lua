-- asteroid.lua
local Asteroid = {}

Asteroid.TILE = 32

local DIRT      = 1
local STONE     = 2
local ANDESITE  = 3
local GRANITE   = 4
local DIORITE   = 5
local TUFF      = 6

Asteroid.PALETTE = {
    [DIRT]     = {0.55, 0.38, 0.22},
    [STONE]    = {0.55, 0.55, 0.58},
    [ANDESITE] = {0.48, 0.48, 0.50},
    [GRANITE]  = {0.62, 0.42, 0.40},
    [DIORITE]  = {0.75, 0.75, 0.78},
    [TUFF]     = {0.28, 0.28, 0.30},
}

Asteroid.MAX_HP = {
    [DIRT]     = 1,
    [STONE]    = 3,
    [ANDESITE] = 4,
    [DIORITE]  = 4,
    [GRANITE]  = 5,
    [TUFF]     = 7,
}

Asteroid.TEXTURE_NAMES = {
    [DIRT]     = "Dirt",
    [STONE]    = "Stone",
    [ANDESITE] = "Andesite",
    [GRANITE]  = "Granite",
    [DIORITE]  = "Diorite",
    [TUFF]     = "Tuff",
}

local ASTEROID_TYPES = {
    {
        name = "Rocky",
        dirtEnd = 0.18, stoneEnd = 0.50, midEnd = 0.78,
        layers = { DIRT, STONE, ANDESITE, GRANITE },
        speckle = { [STONE] = {ANDESITE, 0.35},
                    [ANDESITE] = {STONE, 0.30},
                    [GRANITE] = {DIORITE, 0.35} },
        dirtTint = {0.55, 0.38, 0.22},
    },
    {
        name = "Icy",
        dirtEnd = 0.20, stoneEnd = 0.55, midEnd = 0.80,
        layers = { DIRT, STONE, DIORITE, TUFF },
        speckle = { [STONE] = {DIORITE, 0.40},
                    [DIORITE] = {STONE, 0.35},
                    [TUFF] = {DIORITE, 0.30} },
        dirtTint = {0.55, 0.38, 0.22},
    },
    {
        name = "Metallic",
        dirtEnd = 0.15, stoneEnd = 0.45, midEnd = 0.75,
        layers = { DIRT, ANDESITE, GRANITE, TUFF },
        speckle = { [ANDESITE] = {STONE, 0.30},
                    [GRANITE] = {TUFF, 0.30},
                    [TUFF] = {GRANITE, 0.30} },
        dirtTint = {0.16, 0.16, 0.18},
    },
}

Asteroid.ESCAPE_FACTOR = 2.5

local R_MAX = 0.92

local function makeNoise(seed)
    local ox = seed * 0.1237
    local oy = seed * 0.4561
    return {
        noise = function(self, x, y)
            return love.math.noise(x + ox, y + oy)
        end
    }
end

function Asteroid.computeCenterOfMass(ast)
    local sumX, sumY, count = 0, 0, 0
    local gw, gh = ast.gridW, ast.gridH
    for ly = 0, gh - 1 do
        for lx = 0, gw - 1 do
            local idx = ly * gw + lx + 1
            if ast.tiles[idx] then
                sumX = sumX + lx + 0.5
                sumY = sumY + ly + 0.5
                count = count + 1
            end
        end
    end
    if count == 0 then
        return ast.gridW * 0.5, ast.gridH * 0.5, 0
    end
    return sumX / count, sumY / count, count
end

function Asteroid.getCenterOfMassWorld(ast)
    local localX = (ast.comLx - ast.gridW * 0.5) * Asteroid.TILE
    local localY = (ast.comLy - ast.gridH * 0.5) * Asteroid.TILE
    local ca, sa = math.cos(ast.angle or 0), math.sin(ast.angle or 0)
    local wx = ast.cx + localX * ca - localY * sa
    local wy = ast.cy + localX * sa + localY * ca
    return wx, wy
end

function Asteroid.updateDerived(ast)
    ast.mass = ast.solidCount
    ast.comLx, ast.comLy = Asteroid.computeCenterOfMass(ast)
    local maxD2 = 0
    local gw, gh = ast.gridW, ast.gridH
    for ly = 0, gh - 1 do
        for lx = 0, gw - 1 do
            local idx = ly * gw + lx + 1
            if ast.tiles[idx] then
                local dx = (lx + 0.5) - ast.comLx
                local dy = (ly + 0.5) - ast.comLy
                local d2 = dx * dx + dy * dy
                if d2 > maxD2 then maxD2 = d2 end
            end
        end
    end
    ast.radius = math.max(Asteroid.TILE * 0.5, math.sqrt(maxD2) * Asteroid.TILE)
    ast.influenceRadius = ast.radius * Asteroid.ESCAPE_FACTOR
end

function Asteroid.worldToLocalTile(ast, wx, wy)
    local dx = wx - ast.cx
    local dy = wy - ast.cy
    local ca, sa = math.cos(-(ast.angle or 0)), math.sin(-(ast.angle or 0))
    local lx = dx * ca - dy * sa
    local ly = dx * sa + dy * ca
    local tileX = math.floor(lx / Asteroid.TILE + ast.gridW * 0.5)
    local tileY = math.floor(ly / Asteroid.TILE + ast.gridH * 0.5)
    return tileX, tileY
end

function Asteroid.tileToWorld(ast, lx, ly)
    local localX = (lx + 0.5 - ast.gridW * 0.5) * Asteroid.TILE
    local localY = (ly + 0.5 - ast.gridH * 0.5) * Asteroid.TILE
    local ca, sa = math.cos(ast.angle or 0), math.sin(ast.angle or 0)
    local wx = ast.cx + localX * ca - localY * sa
    local wy = ast.cy + localX * sa + localY * ca
    return wx, wy
end

function Asteroid.tileAtWorld(ast, wx, wy)
    local lx, ly = Asteroid.worldToLocalTile(ast, wx, wy)
    if lx < 0 or ly < 0 or lx >= ast.gridW or ly >= ast.gridH then
        return nil, lx, ly
    end
    local idx = ly * ast.gridW + lx + 1
    return ast.tiles[idx], lx, ly
end

function Asteroid.isSolidAtWorld(ast, wx, wy)
    local t = Asteroid.tileAtWorld(ast, wx, wy)
    return t ~= nil
end

function Asteroid.circleCollides(ast, wx, wy, radius)
    local tilesRadius = math.ceil(radius / Asteroid.TILE) + 1
    local cx, cy = Asteroid.worldToLocalTile(ast, wx, wy)

    local pdx = wx - ast.cx
    local pdy = wy - ast.cy
    local ca, sa = math.cos(-(ast.angle or 0)), math.sin(-(ast.angle or 0))
    local plx = pdx * ca - pdy * sa
    local ply = pdx * sa + pdy * ca

    local halfW = ast.gridW * Asteroid.TILE * 0.5
    local halfH = ast.gridH * Asteroid.TILE * 0.5

    local bestPushX, bestPushY = 0, 0
    local bestOverlap = 0
    local hitAny = false

    for dy = -tilesRadius, tilesRadius do
        for dx = -tilesRadius, tilesRadius do
            local lx = cx + dx
            local ly = cy + dy
            if lx >= 0 and ly >= 0 and lx < ast.gridW and ly < ast.gridH then
                local idx = ly * ast.gridW + lx + 1
                if ast.tiles[idx] then
                    local tMinX = lx * Asteroid.TILE - halfW
                    local tMaxX = tMinX + Asteroid.TILE
                    local tMinY = ly * Asteroid.TILE - halfH
                    local tMaxY = tMinY + Asteroid.TILE

                    local closestX = math.max(tMinX, math.min(plx, tMaxX))
                    local closestY = math.max(tMinY, math.min(ply, tMaxY))

                    local ddx = plx - closestX
                    local ddy = ply - closestY
                    local d2 = ddx * ddx + ddy * ddy

                    if d2 < radius * radius then
                        local d = math.sqrt(d2)
                        local overlap, pushX, pushY

                        if d > 1e-6 then
                            overlap = radius - d
                            pushX = (ddx / d) * overlap
                            pushY = (ddy / d) * overlap
                        else
                            local toLeft   = plx - tMinX
                            local toRight  = tMaxX - plx
                            local toTop    = ply - tMinY
                            local toBottom = tMaxY - ply
                            local minPen = math.min(toLeft, toRight, toTop, toBottom)

                            if minPen == toLeft then
                                pushX = -(toLeft + radius)
                                pushY = 0
                                overlap = toLeft + radius
                            elseif minPen == toRight then
                                pushX = toRight + radius
                                pushY = 0
                                overlap = toRight + radius
                            elseif minPen == toTop then
                                pushX = 0
                                pushY = -(toTop + radius)
                                overlap = toTop + radius
                            else
                                pushX = 0
                                pushY = toBottom + radius
                                overlap = toBottom + radius
                            end
                        end

                        if overlap > bestOverlap then
                            bestOverlap = overlap
                            bestPushX = pushX
                            bestPushY = pushY
                            hitAny = true
                        end
                    end
                end
            end
        end
    end

    if not hitAny then return false end

    local caW, saW = math.cos(ast.angle or 0), math.sin(ast.angle or 0)
    local wpx = bestPushX * caW - bestPushY * saW
    local wpy = bestPushX * saW + bestPushY * caW

    return true, wpx, wpy
end

function Asteroid.generate(cx, cy, gridW, gridH, seed)
    local n = makeNoise(seed)

    local typeIdx = love.math.random(1, #ASTEROID_TYPES)
    local atype   = ASTEROID_TYPES[typeIdx]

    local stretchX = 0.70 + n:noise(1.1, 0.0) * 0.55
    local stretchY = 0.70 + n:noise(2.2, 0.0) * 0.55

    local lobeAmp1 = 0.05 + n:noise(3.3, 0.0) * 0.07
    local lobeAmp2 = 0.03 + n:noise(4.4, 0.0) * 0.05
    local lobeK1   = 2 + math.floor(n:noise(5.5, 0.0) * 3)
    local lobeK2   = 3 + math.floor(n:noise(6.6, 0.0) * 4)
    local lobeP1   = n:noise(7.7, 0.0) * math.pi * 2
    local lobeP2   = n:noise(8.8, 0.0) * math.pi * 2

    local noiseAmp   = 0.04 + n:noise(9.9, 0.0) * 0.05
    local noiseScale = 1.5 + n:noise(10.1, 0.0) * 2.0

    local eggAmp = (n:noise(11.2, 0.0) - 0.5) * 0.12

    local maxUp = 1
        + math.abs(lobeAmp1) + math.abs(lobeAmp2)
        + math.abs(eggAmp)   + noiseAmp
    local scaleFit = R_MAX / maxUp

    local function edgeRadius(theta)
        local c, s = math.cos(theta), math.sin(theta)
        local r = 1.0 / math.sqrt((c / stretchX)^2 + (s / stretchY)^2)
        r = r * (1 + lobeAmp1 * math.sin(theta * lobeK1 + lobeP1)
                   + lobeAmp2 * math.cos(theta * lobeK2 + lobeP2))
        r = r * (1 + eggAmp * c)
        local nx = c * noiseScale + 17
        local ny = s * noiseScale + 29
        r = r * (1 + (n:noise(nx, ny) - 0.5) * 2 * noiseAmp)
        r = r * scaleFit
        if r > R_MAX then r = R_MAX end
        if r < 0.30 then r = 0.30 end
        return r
    end

    local halfW = gridW * 0.5
    local halfH = gridH * 0.5
    local norm  = math.max(halfW, halfH)

    local ANG_STEPS = 512
    local radiusTable = {}
    for i = 0, ANG_STEPS - 1 do
        local a = (i / ANG_STEPS) * math.pi * 2 - math.pi
        radiusTable[i] = edgeRadius(a)
    end
    local function rAt(theta)
        local t = (theta + math.pi) / (math.pi * 2) * ANG_STEPS
        local i0 = math.floor(t) % ANG_STEPS
        return radiusTable[i0]
    end

    local dRaw = {}
    local dMin, dMax = math.huge, -math.huge

    for ly = 0, gridH - 1 do
        local ny = (ly - halfH + 0.5) / norm
        for lx = 0, gridW - 1 do
            local nx = (lx - halfW + 0.5) / norm
            local idx = ly * gridW + lx + 1
            local theta = math.atan2(ny, nx)
            local rEdge = rAt(theta)
            local dx = nx / stretchX
            local dy = ny / stretchY
            local d = math.sqrt(dx * dx + dy * dy) / rEdge
            if d <= 1.0 then
                dRaw[idx] = d
                if d < dMin then dMin = d end
                if d > dMax then dMax = d end
            end
        end
    end

    if dMax - dMin < 1e-6 then dMax = dMin + 1e-6 end

    local ast = {
        cx = cx, cy = cy,
        gridW = gridW, gridH = gridH,
        seed = seed,
        typeIdx = typeIdx,
        typeName = atype.name,
        dirtTint = atype.dirtTint,
        tiles = {},
        hp    = {},
        dist  = {},
        solidCount = 0,
        vx = 0, vy = 0,
        va = 0,
        angle = 0,
        comLx = gridW * 0.5,
        comLy = gridH * 0.5,
    }

    local function layerForT(t)
        if t < atype.dirtEnd  then return atype.layers[1] end
        if t < atype.stoneEnd then return atype.layers[2] end
        if t < atype.midEnd   then return atype.layers[3] end
        return atype.layers[4]
    end

    for ly = 0, gridH - 1 do
        for lx = 0, gridW - 1 do
            local idx = ly * gridW + lx + 1
            local d = dRaw[idx]
            if d then
                local t = 1.0 - (d - dMin) / (dMax - dMin)
                local tile = layerForT(t)
                local sp = atype.speckle[tile]
                if sp then
                    local v = n:noise(lx * 0.18, ly * 0.18 + 50)
                    if v > (1 - sp[2]) then
                        tile = sp[1]
                    end
                end
                ast.tiles[idx] = tile
                ast.hp[idx]    = Asteroid.MAX_HP[tile] or 1
                ast.dist[idx]  = t
                ast.solidCount = ast.solidCount + 1
            end
        end
    end

    ast.radius = math.max(gridW, gridH) * Asteroid.TILE * 0.5
    ast.mass   = ast.solidCount
    ast.influenceRadius = ast.radius * Asteroid.ESCAPE_FACTOR

    ast.comLx, ast.comLy = Asteroid.computeCenterOfMass(ast)

    return ast
end

local SPLIT_MIN_TILES = 2

local function findComponents(ast)
    local gw, gh = ast.gridW, ast.gridH
    local total = gw * gh
    local visited = {}
    local components = {}

    for startIdx = 1, total do
        if ast.tiles[startIdx] and not visited[startIdx] then
            local comp = {}
            local queue = {startIdx}
            visited[startIdx] = true
            local qi = 1
            while qi <= #queue do
                local idx = queue[qi]
                qi = qi + 1
                comp[#comp + 1] = idx

                local ly = math.floor((idx - 1) / gw)
                local lx = (idx - 1) % gw

                if lx > 0 and ast.tiles[idx - 1] and not visited[idx - 1] then
                    visited[idx - 1] = true
                    queue[#queue + 1] = idx - 1
                end
                if lx < gw - 1 and ast.tiles[idx + 1] and not visited[idx + 1] then
                    visited[idx + 1] = true
                    queue[#queue + 1] = idx + 1
                end
                if ly > 0 and ast.tiles[idx - gw] and not visited[idx - gw] then
                    visited[idx - gw] = true
                    queue[#queue + 1] = idx - gw
                end
                if ly < gh - 1 and ast.tiles[idx + gw] and not visited[idx + gw] then
                    visited[idx + gw] = true
                    queue[#queue + 1] = idx + gw
                end
            end
            components[#components + 1] = comp
        end
    end

    return components
end

local function buildFragment(ast, comp, oldComX, oldComY)
    local gw, gh = ast.gridW, ast.gridH
    local oldCx, oldCy = ast.cx, ast.cy
    local oldAngle = ast.angle or 0

    local minLx, maxLx = gw, 0
    local minLy, maxLy = gh, 0
    local sumLx, sumLy, cnt = 0, 0, 0

    for _, idx in ipairs(comp) do
        local ly = math.floor((idx - 1) / gw)
        local lx = (idx - 1) % gw
        if lx < minLx then minLx = lx end
        if lx > maxLx then maxLx = lx end
        if ly < minLy then minLy = ly end
        if ly > maxLy then maxLy = ly end
        sumLx = sumLx + lx + 0.5
        sumLy = sumLy + ly + 0.5
        cnt = cnt + 1
    end

    local newW = maxLx - minLx + 1
    local newH = maxLy - minLy + 1

    local bboxCenterLx = (minLx + maxLx + 1) * 0.5
    local bboxCenterLy = (minLy + maxLy + 1) * 0.5

    local localX = (bboxCenterLx - gw * 0.5) * Asteroid.TILE
    local localY = (bboxCenterLy - gh * 0.5) * Asteroid.TILE
    local ca, sa = math.cos(oldAngle), math.sin(oldAngle)
    local newCx = oldCx + localX * ca - localY * sa
    local newCy = oldCy + localX * sa + localY * ca

    local relX = newCx - oldComX
    local relY = newCy - oldComY
    local newVx = ast.vx - ast.va * relY
    local newVy = ast.vy + ast.va * relX

    local newAst = {
        cx = newCx, cy = newCy,
        gridW = newW, gridH = newH,
        seed = ast.seed + love.math.random(0, 1000),
        typeIdx = ast.typeIdx,
        typeName = ast.typeName,
        dirtTint = ast.dirtTint,
        tiles = {},
        hp    = {},
        dist  = {},
        solidCount = 0,
        vx = newVx,
        vy = newVy,
        va = ast.va or 0,
        angle = oldAngle,
        lightLevel = nil,
    }

    for _, idx in ipairs(comp) do
        local ly = math.floor((idx - 1) / gw)
        local lx = (idx - 1) % gw
        local nlx = lx - minLx
        local nly = ly - minLy
        local nidx = nly * newW + nlx + 1
        newAst.tiles[nidx] = ast.tiles[idx]
        newAst.hp[nidx]    = ast.hp[idx]
        newAst.dist[nidx]  = ast.dist[idx]
        newAst.solidCount  = newAst.solidCount + 1
    end

    newAst.radius = math.max(newW, newH) * Asteroid.TILE * 0.5
    newAst.mass   = newAst.solidCount
    newAst.influenceRadius = newAst.radius * Asteroid.ESCAPE_FACTOR
    Asteroid.updateDerived(newAst)

    return newAst
end

function Asteroid.split(ast)
    local components = findComponents(ast)

    if #components <= 1 then
        return { ast }, false
    end

    local oldComX, oldComY = Asteroid.getCenterOfMassWorld(ast)
    local newAsteroids = {}

    for _, comp in ipairs(components) do
        if #comp >= SPLIT_MIN_TILES then
            newAsteroids[#newAsteroids + 1] = buildFragment(ast, comp, oldComX, oldComY)
        else
            for _, idx in ipairs(comp) do
                ast.tiles[idx] = nil
                ast.hp[idx]    = nil
                ast.solidCount = ast.solidCount - 1
            end
        end
    end

    if #newAsteroids == 0 then
        return { ast }, false
    end

    return newAsteroids, true
end

function Asteroid.findTileInAsteroids(asteroids, oldAst, oldLx, oldLy)
    for _, a in ipairs(asteroids) do
        if a == oldAst then
            local idx = oldLy * a.gridW + oldLx + 1
            if a.tiles[idx] then
                return a, oldLx, oldLy
            end
        end
    end
    return nil
end

return Asteroid



