-- main.lua
local Asteroid = require("asteroid")
local Player   = require("player")
local LightSystem = require("light_system")

local SIZE_SMALL  = 24
local SIZE_MEDIUM = 48
local SIZE_LARGE  = 96

local TEXTURES     = {}
local HAS_TEXTURE  = {}
local TEX_W, TEX_H = {}, {}

local HP_TEXT = {}
local HP_TEXT_W = {}

local FPS_TEXT
local fpsFrames, fpsTimer, fpsValue = 0, 0, 0

local HUD_LINE1, HUD_LINE2, HUD_LINE3

local asteroids = {}
local player = Player.new()
local lightSys = LightSystem.new()

local camera = {
    x = 0, y = 0,
    zoom = 1.0,
    zoomMin = 0.25,
    zoomMax = 4.0,
    zoomStep = 1.12,
    angle = 0,
    targetAngle = 0,
}

local CAM_ANGLE_LERP = 8.0

local MINING_INTERVAL = 0.1
local MINING_RANGE = Asteroid.TILE * 2.5

local miningTimer = 0
local miningTarget = nil

local ropePrevRMB = false

local function tryLoadTexture(name)
    if not name then return nil end
    for _, ext in ipairs({".png", ".jpg", ".jpeg"}) do
        local path = "res/" .. name .. ext
        if love.filesystem.getInfo(path) then
            local ok, img = pcall(love.graphics.newImage, path)
            if ok and img then
                img:setFilter("nearest", "nearest")
                return img
            end
        end
    end
    return nil
end

local function loadTextures()
    TEXTURES, HAS_TEXTURE, TEX_W, TEX_H = {}, {}, {}, {}
    for id, name in pairs(Asteroid.TEXTURE_NAMES) do
        local img = tryLoadTexture(name)
        if img then
            TEXTURES[id]    = img
            HAS_TEXTURE[id] = true
            TEX_W[id], TEX_H[id] = img:getDimensions()
        else
            HAS_TEXTURE[id] = false
        end
    end
end

local function buildTextCache()
    HP_TEXT, HP_TEXT_W = {}, {}

    local baseFont = love.graphics.getFont()
    local fsize    = baseFont and baseFont:getHeight() or 12

    local hpFont = love.graphics.newFont(math.max(7, math.floor(fsize * 0.5)))
    hpFont:setFilter("nearest", "nearest")
    for v = 0, 20 do
        local s = tostring(v)
        HP_TEXT[v] = love.graphics.newText(hpFont, s)
        HP_TEXT_W[v] = hpFont:getWidth(s)
    end
end

local function buildFpsText()
    FPS_TEXT = love.graphics.newText(love.graphics.getFont(), "FPS: 0")
end

local function screenToWorld(mx, my)
    local W, H = love.graphics.getWidth(), love.graphics.getHeight()
    local cx, cy = W * 0.5, H * 0.5
    local sx = (mx - cx) / camera.zoom
    local sy = (my - cy) / camera.zoom
    local ca, sa = math.cos(-camera.angle), math.sin(-camera.angle)
    local rx = sx * ca - sy * sa
    local ry = sx * sa + sy * ca
    return rx + camera.x, ry + camera.y
end

local function findTileUnderCursor()
    local mx, my = love.mouse.getPosition()
    local worldX, worldY = screenToWorld(mx, my)

    for _, ast in ipairs(asteroids) do
        local lx, ly = Asteroid.worldToLocalTile(ast, worldX, worldY)
        if lx >= 0 and ly >= 0 and lx < ast.gridW and ly < ast.gridH then
            local idx = ly * ast.gridW + lx + 1
            if ast.tiles[idx] then
                return ast, lx, ly, idx, worldX, worldY
            end
        end
    end
    return nil
end

local function cleanupEmptyAsteroids()
    local i = 1
    while i <= #asteroids do
        if asteroids[i].solidCount == 0 then
            if player.rope.targetAst == asteroids[i] then
                Player.detachRope(player)
            end
            table.remove(asteroids, i)
        else
            i = i + 1
        end
    end
end

local function spawnAsteroid(sizeTiles)
    asteroids = {}
    local ast = Asteroid.generate(0, 0, sizeTiles, sizeTiles, love.math.random(1, 1000000))
    asteroids[1] = ast

    Player.spawnAsteroid(asteroids, sizeTiles, player)

    camera.x = player.x
    camera.y = player.y
    camera.zoom = 1.0
    camera.angle = -math.atan2(player.gravityY, player.gravityX) - math.pi * 0.5 + math.pi
    camera.targetAngle = camera.angle

    LightSystem.update(lightSys, asteroids, player, Asteroid.TILE)

    HUD_LINE1 = string.format("Asteroid %dx%d [%s] seed=%d tiles=%d",
        sizeTiles, sizeTiles, ast.typeName, ast.seed, ast.solidCount)
    HUD_LINE3 = string.format("Radius: %.0f  Mass: %d", ast.radius, ast.mass)
end

local function updateMining(dt)
    if not love.mouse.isDown(1) then
        miningTimer = 0
        miningTarget = nil
        return
    end

    local ast, lx, ly, idx = findTileUnderCursor()
    if not ast then
        miningTimer = 0
        miningTarget = nil
        return
    end

    local tileCX, tileCY = Asteroid.tileToWorld(ast, lx, ly)
    local ddx = tileCX - player.x
    local ddy = tileCY - player.y
    local distToPlayer = math.sqrt(ddx * ddx + ddy * ddy)
    if distToPlayer > MINING_RANGE then
        miningTimer = 0
        miningTarget = nil
        return
    end

    miningTarget = { ast = ast, idx = idx, lx = lx, ly = ly }

    miningTimer = miningTimer + dt
    while miningTimer >= MINING_INTERVAL do
        miningTimer = miningTimer - MINING_INTERVAL

        if ast.tiles[idx] then
            ast.hp[idx] = ast.hp[idx] - 1
            if ast.hp[idx] <= 0 then
                ast.tiles[idx] = nil
                ast.hp[idx]    = nil
                ast.solidCount = ast.solidCount - 1
                Asteroid.updateDerived(ast)

                local r = player.rope
                local wasAttached = r.attached
                local hookWorldX, hookWorldY = nil, nil
                if wasAttached and r.targetAst then
                    hookWorldX, hookWorldY = Asteroid.tileToWorld(r.targetAst, r.targetLx, r.targetLy)
                end

                local parts, split = Asteroid.split(ast)
                if split then
                    for i, a in ipairs(asteroids) do
                        if a == ast then
                            table.remove(asteroids, i)
                            break
                        end
                    end
                    for _, p in ipairs(parts) do
                        asteroids[#asteroids + 1] = p
                    end
                end

                if wasAttached and hookWorldX then
                    local foundAst, foundLx, foundLy = nil, nil, nil
                    for _, a in ipairs(asteroids) do
                        local flx, fly = Asteroid.worldToLocalTile(a, hookWorldX, hookWorldY)
                        if flx >= 0 and fly >= 0 and flx < a.gridW and fly < a.gridH then
                            local tidx = fly * a.gridW + flx + 1
                            if a.tiles[tidx] then
                                foundAst, foundLx, foundLy = a, flx, fly
                                break
                            end
                        end
                    end
                    if foundAst then
                        r.targetAst = foundAst
                        r.targetLx = foundLx
                        r.targetLy = foundLy
                        local cx2, cy2 = Asteroid.tileToWorld(foundAst, foundLx, foundLy)
                        r.x = cx2
                        r.y = cy2
                    else
                        Player.detachRope(player)
                    end
                end

                cleanupEmptyAsteroids()
                LightSystem.update(lightSys, asteroids, player, Asteroid.TILE)

                miningTarget = nil
                miningTimer = 0
                return
            end
        else
            miningTarget = nil
            miningTimer = 0
            return
        end
    end
end

local function updateAsteroids(dt)
    for _, ast in ipairs(asteroids) do
        if math.abs(ast.vx) > 0.01 or math.abs(ast.vy) > 0.01 then
            ast.cx = ast.cx + ast.vx * dt
            ast.cy = ast.cy + ast.vy * dt
            ast.vx = ast.vx * (1 - 0.4 * dt)
            ast.vy = ast.vy * (1 - 0.4 * dt)
            if math.abs(ast.vx) < 0.5 then ast.vx = 0 end
            if math.abs(ast.vy) < 0.5 then ast.vy = 0 end
        end
        if math.abs(ast.va) > 0.0001 then
            ast.angle = ast.angle + ast.va * dt
            ast.va = ast.va * (1 - 0.5 * dt)
            if math.abs(ast.va) < 0.0001 then ast.va = 0 end
        end
    end
end

local function updateCamera(dt)
    camera.x = player.x
    camera.y = player.y

    if player.gravityMag > 1e-6 then
        camera.targetAngle = -math.atan2(player.gravityY, player.gravityX) - math.pi * 0.5 + math.pi
    end

    local diff = camera.targetAngle - camera.angle
    while diff >  math.pi do diff = diff - math.pi * 2 end
    while diff < -math.pi do diff = diff + math.pi * 2 end
    local t = 1 - math.exp(-CAM_ANGLE_LERP * dt)
    camera.angle = camera.angle + diff * t
end

function love.load()
    love.window.setMode(1000, 700, { resizable = true })
    love.window.setTitle("Perlin Asteroids")
    love.graphics.setDefaultFilter("nearest", "nearest")

    buildTextCache()
    loadTextures()
    buildFpsText()

    HUD_LINE2 = "[1/2/3] size  [SPACE] jump  [LMB] mine  [RMB] rope  [W/S] reel  [wheel] zoom  [L] light"
    spawnAsteroid(SIZE_MEDIUM)
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    elseif key == "1" then
        spawnAsteroid(SIZE_SMALL)
    elseif key == "2" then
        spawnAsteroid(SIZE_MEDIUM)
    elseif key == "3" then
        spawnAsteroid(SIZE_LARGE)
    elseif key == "l" then
        lightSys.enabled = not lightSys.enabled
    end
end

function love.wheelmoved(dx, dy)
    if dy > 0 then
        camera.zoom = camera.zoom * camera.zoomStep
    elseif dy < 0 then
        camera.zoom = camera.zoom / camera.zoomStep
    end
    if camera.zoom < camera.zoomMin then camera.zoom = camera.zoomMin end
    if camera.zoom > camera.zoomMax then camera.zoom = camera.zoomMax end
end

function love.update(dt)
    if dt > 0.1 then dt = 0.1 end

    fpsFrames = fpsFrames + 1
    fpsTimer  = fpsTimer + dt
    if fpsTimer >= 0.5 then
        fpsValue  = fpsFrames / fpsTimer
        fpsTimer  = 0
        fpsFrames = 0
        if FPS_TEXT then
            FPS_TEXT:set(string.format("FPS: %.0f", fpsValue))
        end
    end

    local rmbDown = love.mouse.isDown(2)
    if rmbDown and not ropePrevRMB then
        local mx, my = love.mouse.getPosition()
        local worldX, worldY = screenToWorld(mx, my)
        Player.toggleRope(player, worldX, worldY)
    end
    ropePrevRMB = rmbDown

    updateMining(dt)
    updateAsteroids(dt)

    local inputAngle = camera.angle
    if player.gravityMag > 1e-6 then
        local target = -math.atan2(player.gravityY, player.gravityX) - math.pi * 0.5 + math.pi
        local diff = target - camera.angle
        while diff >  math.pi do diff = diff - math.pi * 2 end
        while diff < -math.pi do diff = diff + math.pi * 2 end
        if math.abs(diff) > math.pi * 0.5 then
            inputAngle = target
        end
    end

    Player.update(player, dt, asteroids, inputAngle)
    updateCamera(dt)

    LightSystem.update(lightSys, asteroids, player, Asteroid.TILE)
end

local function drawAsteroid(ast, viewCX, viewCY, viewRadius)
    local gw, gh = ast.gridW, ast.gridH
    local halfW = gw * Asteroid.TILE * 0.5
    local halfH = gh * Asteroid.TILE * 0.5
    local ca, sa = math.cos(ast.angle or 0), math.sin(ast.angle or 0)

    local tiles = ast.tiles
    local minWX = viewCX - viewRadius
    local maxWX = viewCX + viewRadius
    local minWY = viewCY - viewRadius
    local maxWY = viewCY + viewRadius

    local lsEnabled = lightSys.enabled
    local lsLevel = ast.lightLevel

    local dirtTint = ast.dirtTint

    for ly = 0, gh - 1 do
        for lx = 0, gw - 1 do
            local idx = ly * gw + lx + 1
            local tile = tiles[idx]
            if tile then
                local localX = (lx + 0.5) * Asteroid.TILE - halfW
                local localY = (ly + 0.5) * Asteroid.TILE - halfH
                local wx = ast.cx + localX * ca - localY * sa
                local wy = ast.cy + localX * sa + localY * ca

                if wx + Asteroid.TILE >= minWX and wx - Asteroid.TILE <= maxWX
                   and wy + Asteroid.TILE >= minWY and wy - Asteroid.TILE <= maxWY then

                    local shade = 1.0
                    if lsEnabled and lsLevel then
                        local lit = lsLevel[idx] or 0
                        shade = 0.1 + 0.9 * (lit / 10)
                    end

                    love.graphics.push()
                    love.graphics.translate(wx, wy)
                    love.graphics.rotate(ast.angle or 0)

                    if HAS_TEXTURE[tile] then
                        love.graphics.setColor(shade, shade, shade, 1)
                        local tex = TEXTURES[tile]
                        love.graphics.draw(tex, -Asteroid.TILE * 0.5, -Asteroid.TILE * 0.5, 0,
                            Asteroid.TILE / TEX_W[tile], Asteroid.TILE / TEX_H[tile])
                    else
                        local c = Asteroid.PALETTE[tile]
                        if c then
                            local r, g, b
                            if tile == 1 and dirtTint then
                                r, g, b = dirtTint[1], dirtTint[2], dirtTint[3]
                            else
                                r, g, b = c[1], c[2], c[3]
                            end
                            love.graphics.setColor(r * shade, g * shade, b * shade, 1)
                            love.graphics.rectangle("fill", -Asteroid.TILE * 0.5, -Asteroid.TILE * 0.5, Asteroid.TILE, Asteroid.TILE)
                        end
                    end

                    local hpVal = ast.hp[idx]
                    if hpVal and hpVal < (Asteroid.MAX_HP[tile] or 1) and hpVal > 0 then
                        local t = HP_TEXT[hpVal]
                        if t then
                            local ox = -HP_TEXT_W[hpVal] * 0.5
                            local oy = -t:getHeight() * 0.5
                            love.graphics.setColor(0, 0, 0, 0.85)
                            love.graphics.draw(t, ox + 1, oy + 1)
                            love.graphics.setColor(1, 1, 1, 1)
                            love.graphics.draw(t, ox, oy)
                        end
                    end

                    love.graphics.pop()
                end
            end
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

local function drawPlayer()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.push()
    love.graphics.translate(player.x, player.y)
    love.graphics.rotate(player.angle)

    love.graphics.setColor(0.9, 0.85, 0.4, 1)
    love.graphics.circle("fill", 0, 0, Player.RADIUS)

    love.graphics.setColor(0.15, 0.1, 0.05, 1)
    love.graphics.circle("line", 0, 0, Player.RADIUS)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", -2, -Player.RADIUS - 4, 4, 6)
    love.graphics.rectangle("fill", -2, Player.RADIUS - 2, 4, 6)

    love.graphics.pop()
end

local function drawCenterOfMass()
    for _, ast in ipairs(asteroids) do
        local comX, comY = Asteroid.getCenterOfMassWorld(ast)
        love.graphics.setColor(1, 0.3, 0.9, 0.5)
        love.graphics.circle("line", comX, comY, 4)
        love.graphics.line(comX - 6, comY, comX + 6, comY)
        love.graphics.line(comX, comY - 6, comX, comY + 6)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

local function drawHighlight(target, color)
    if not target then return end
    local ast = target.ast
    local lx = target.lx
    local ly = target.ly
    if not ast or not lx or not ly then return end
    local wx, wy = Asteroid.tileToWorld(ast, lx, ly)

    love.graphics.push()
    love.graphics.translate(wx, wy)
    love.graphics.rotate(ast.angle or 0)
    love.graphics.setColor(color[1], color[2], color[3], color[4])
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", -Asteroid.TILE * 0.5, -Asteroid.TILE * 0.5, Asteroid.TILE, Asteroid.TILE)
    love.graphics.setLineWidth(1)
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1, 1)
end

local function drawRope()
    local r = player.rope
    if not r.active then return end

    love.graphics.setColor(0.9, 0.9, 0.2, 0.9)
    love.graphics.setLineWidth(2)
    love.graphics.line(player.x, player.y, r.x, r.y)

    if r.attached then
        love.graphics.setColor(0.2, 1.0, 0.2, 1.0)
        love.graphics.circle("fill", r.x, r.y, 5)
    else
        love.graphics.setColor(1.0, 0.9, 0.2, 1.0)
        love.graphics.circle("fill", r.x, r.y, 4)
    end
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

function love.draw()
    local W, H = love.graphics.getWidth(), love.graphics.getHeight()

    love.graphics.push()
    love.graphics.translate(W * 0.5, H * 0.5)
    love.graphics.scale(camera.zoom, camera.zoom)
    love.graphics.rotate(camera.angle)
    love.graphics.translate(-camera.x, -camera.y)

    local viewRadius = math.max(W, H) / camera.zoom + Asteroid.TILE * 4
    for _, ast in ipairs(asteroids) do
        drawAsteroid(ast, camera.x, camera.y, viewRadius)
    end

    drawCenterOfMass()
    drawHighlight(miningTarget, {1, 0.3, 0.3, 0.8})
    drawRope()
    drawPlayer()

    love.graphics.pop()

    local mx, my = love.mouse.getPosition()
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.circle("line", mx, my, 6)
    love.graphics.setColor(1, 1, 1, 1)

    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", 0, 0, 860, 100)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(HUD_LINE1 or "", 10, 10)
    love.graphics.print(HUD_LINE2 or "", 10, 30)
    love.graphics.print(HUD_LINE3 or "", 10, 50)
    local mode = player.inZeroG and "ZERO-G" or "GRAVITY"
    local r = player.rope
    local ropeState = ""
    if r.active then
        ropeState = r.attached and " [ROPE-HOOKED]" or " [ROPE-FLYING]"
    end
    local lightState = lightSys.enabled and "ON" or "OFF"
    love.graphics.print(string.format("Player: %.0f, %.0f  Vel: %.0f  Zoom: %.2fx  [%s]%s  Asteroids: %d  Light: %s",
        player.x, player.y,
        math.sqrt(player.vx * player.vx + player.vy * player.vy),
        camera.zoom, mode, ropeState, #asteroids, lightState), 10, 70)

    if FPS_TEXT then
        local fw = FPS_TEXT:getWidth()
        local fh = FPS_TEXT:getHeight()
        love.graphics.setColor(0, 0, 0, 0.55)
        love.graphics.rectangle("fill", W - fw - 20, 8, fw + 12, fh + 8)
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(FPS_TEXT, W - fw - 14, 12)
    end
end





