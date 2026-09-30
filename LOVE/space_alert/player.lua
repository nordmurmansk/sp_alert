-- player.lua
local Asteroid = require("asteroid")

local Player = {}

Player.RADIUS = 10
Player.SPEED = 220
Player.GRAVITY_BASE = 320

Player.JUMP_IMPULSE_BASE = 280
Player.JUMP_COOLDOWN = 0.25
Player.COYOTE_TIME = 0.12

Player.GRAVITY_THRESHOLD = 40
Player.ZERO_G_SPEED = 220
Player.ZERO_G_MAX_SPEED = 900

Player.AIR_CONTROL = 0.6
Player.GROUND_ACCEL = 6

Player.ROPE_MAX_LEN      = Asteroid.TILE * 10
Player.ROPE_SHOOT_SPEED  = 1400
Player.ROPE_REEL_SPEED   = 320
Player.ROPE_SWING_ACCEL  = 900
Player.ROPE_MAX_SWING    = 600
Player.ROPE_DAMPING      = 0.6

local GROUND_DOT_MAX = -0.5
local GROUND_MEMORY = 0.12

function Player.new()
    return {
        x = 0, y = 0,
        vx = 0, vy = 0,
        angle = 0,
        onGround = false,
        landed = false,
        jumpTimer = 0,
        coyoteTimer = 0,
        wasOnGround = false,
        inZeroG = false,
        groundNormalX = 0, groundNormalY = -1,
        groundMemory = 0,
        gravityX = 0, gravityY = 1,
        gravityMag = Player.GRAVITY_BASE,
        lastGravityX = 0,
        lastGravityY = 1,

        rope = {
            active = false,
            attached = false,
            x = 0, y = 0,
            vx = 0, vy = 0,
            targetAst = nil,
            targetLx = 0, targetLy = 0,
            len = 0,
            reeling = false,
        },
    }
end

function Player.computeGravityAt(asteroids, wx, wy)
    local gx, gy = 0, 0
    local maxG = 0

    for _, ast in ipairs(asteroids) do
        local comX, comY = Asteroid.getCenterOfMassWorld(ast)
        local dx = comX - wx
        local dy = comY - wy
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < 1e-6 then dist = 1e-6 end

        local R = ast.radius
        local gSurface = Player.GRAVITY_BASE * (ast.mass / 1000) / math.max(0.5, (R / 400))

        if dist <= ast.influenceRadius then
            local gMag
            if dist <= R then
                gMag = gSurface * (dist / R)
            else
                local t = (dist - R) / (ast.influenceRadius - R)
                t = math.max(0, math.min(1, t))
                gMag = gSurface * (1 - t) * (1 - t)
            end

            if gMag > 500 then gMag = 500 end

            local ux = dx / dist
            local uy = dy / dist

            gx = gx + ux * gMag
            gy = gy + uy * gMag

            if gMag > maxG then maxG = gMag end
        end
    end

    return gx, gy, maxG
end

function Player.spawnAsteroid(asteroids, sizeTiles, player)
    local ast = asteroids[1]

    local px, py, nx, ny
    local found = false

    for attempt = 1, 200 do
        local angle = love.math.random() * math.pi * 2
        local dirX, dirY = math.cos(angle), math.sin(angle)

        local comX, comY = Asteroid.getCenterOfMassWorld(ast)
        local maxR = math.max(ast.gridW, ast.gridH) * Asteroid.TILE * 0.75
        local lastSolidR = 0
        local step = Asteroid.TILE * 0.25
        for r = 0, maxR, step do
            local qx = comX + dirX * r
            local qy = comY + dirY * r
            if Asteroid.isSolidAtWorld(ast, qx, qy) then
                lastSolidR = r
            end
        end

        local spawnR = lastSolidR + Player.RADIUS + 6
        local qx = comX + dirX * spawnR
        local qy = comY + dirY * spawnR

        local hit = Asteroid.circleCollides(ast, qx, qy, Player.RADIUS + 2)
        if not hit then
            px, py, nx, ny = qx, qy, dirX, dirY
            found = true
            break
        end
    end

    if not found then
        local comX, comY = Asteroid.getCenterOfMassWorld(ast)
        px, py, nx, ny = comX, comY - ast.radius * 1.5, 0, -1
    end

    player.x = px
    player.y = py
    player.vx = 0
    player.vy = 0
    player.angle = math.atan2(ny, nx) + math.pi * 0.5
    player.onGround = false
    player.landed = false
    player.jumpTimer = 0
    player.coyoteTimer = 0
    player.wasOnGround = false
    player.inZeroG = false
    player.groundNormalX = -nx
    player.groundNormalY = -ny
    player.groundMemory = 0
    player.gravityX = nx
    player.gravityY = ny
    player.gravityMag = Player.GRAVITY_BASE
    player.lastGravityX = nx
    player.lastGravityY = ny

    Player.detachRope(player)

    return px, py, nx, ny
end

function Player.detachRope(player)
    local r = player.rope
    r.active = false
    r.attached = false
    r.targetAst = nil
    r.reeling = false
end

function Player.fireRope(player, worldX, worldY)
    local r = player.rope
    local dx = worldX - player.x
    local dy = worldY - player.y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 1e-6 then dist = 1e-6 end

    r.active = true
    r.attached = false
    r.reeling = false
    r.x = player.x
    r.y = player.y
    r.vx = (dx / dist) * Player.ROPE_SHOOT_SPEED
    r.vy = (dy / dist) * Player.ROPE_SHOOT_SPEED
    r.targetAst = nil
    r.len = 0
end

function Player.toggleRope(player, worldX, worldY)
    if player.rope.active then
        Player.detachRope(player)
    else
        Player.fireRope(player, worldX, worldY)
    end
end

local function updateRope(player, dt, asteroids)
    local r = player.rope
    if not r.active then return end

    if love.keyboard.isDown("s", "down") then
        r.reeling = true
    else
        r.reeling = false
    end

    if not r.attached then
        r.x = r.x + r.vx * dt
        r.y = r.y + r.vy * dt

        local dx = r.x - player.x
        local dy = r.y - player.y
        local distFromPlayer = math.sqrt(dx * dx + dy * dy)
        if distFromPlayer > Player.ROPE_MAX_LEN then
            Player.detachRope(player)
            return
        end

        for _, ast in ipairs(asteroids) do
            local lx, ly = Asteroid.worldToLocalTile(ast, r.x, r.y)
            if lx >= 0 and ly >= 0 and lx < ast.gridW and ly < ast.gridH then
                local idx = ly * ast.gridW + lx + 1
                if ast.tiles[idx] then
                    r.attached = true
                    r.targetAst = ast
                    r.targetLx = lx
                    r.targetLy = ly
                    local tileCX, tileCY = Asteroid.tileToWorld(ast, lx, ly)
                    r.x = tileCX
                    r.y = tileCY
                    local ddx = r.x - player.x
                    local ddy = r.y - player.y
                    r.len = math.sqrt(ddx * ddx + ddy * ddy)
                    return
                end
            end
        end
        return
    end

    if r.targetAst then
        local tidx = r.targetLy * r.targetAst.gridW + r.targetLx + 1
        if not r.targetAst.tiles[tidx] then
            Player.detachRope(player)
            return
        end

        local tileCX, tileCY = Asteroid.tileToWorld(r.targetAst, r.targetLx, r.targetLy)
        r.x = tileCX
        r.y = tileCY

        local dx = player.x - r.x
        local dy = player.y - r.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < 1e-6 then dist = 1e-6 end
        local ux, uy = dx / dist, dy / dist

        local tx = -uy
        local ty = ux
        local vRad = player.vx * ux + player.vy * uy
        local vTan = player.vx * tx + player.vy * ty

        if love.keyboard.isDown("w", "up") then
            r.len = r.len + Player.ROPE_REEL_SPEED * dt
            if r.len > Player.ROPE_MAX_LEN then
                r.len = Player.ROPE_MAX_LEN
            end
        elseif r.reeling then
            local newLen = r.len - Player.ROPE_REEL_SPEED * dt
            if newLen < Player.RADIUS + 2 then
                newLen = Player.RADIUS + 2
            end
            r.len = newLen
        end

        if dist < r.len then
            local excess = r.len - dist
            vRad = vRad + excess / dt
        elseif dist > r.len then
            local correction = dist - r.len
            vRad = vRad - correction / dt
        end

        local inputTangent = 0
        if love.keyboard.isDown("a", "left")  then inputTangent = inputTangent - 1 end
        if love.keyboard.isDown("d", "right") then inputTangent = inputTangent + 1 end
        vTan = vTan + inputTangent * Player.ROPE_SWING_ACCEL * dt
        if vTan >  Player.ROPE_MAX_SWING then vTan =  Player.ROPE_MAX_SWING end
        if vTan < -Player.ROPE_MAX_SWING then vTan = -Player.ROPE_MAX_SWING end

        player.vx = ux * vRad + tx * vTan
        player.vy = uy * vRad + ty * vTan
    else
        Player.detachRope(player)
    end
end

local function screenInput(cameraAngle)
    local ix, iy = 0, 0
    if love.keyboard.isDown("a", "left")  then ix = ix - 1 end
    if love.keyboard.isDown("d", "right") then ix = ix + 1 end
    if love.keyboard.isDown("w", "up")    then iy = iy - 1 end
    if love.keyboard.isDown("s", "down")  then iy = iy + 1 end
    if ix == 0 and iy == 0 then return 0, 0 end

    local ca, sa = math.cos(-cameraAngle), math.sin(-cameraAngle)
    local wx = ix * ca - iy * sa
    local wy = ix * sa + iy * ca
    return wx, wy
end

function Player.update(player, dt, asteroids, cameraAngle)
    if #asteroids == 0 then return end

    if player.jumpTimer > 0 then
        player.jumpTimer = player.jumpTimer - dt
    end
    if player.groundMemory > 0 then
        player.groundMemory = player.groundMemory - dt
    end

    local gx, gy, gMag = Player.computeGravityAt(asteroids, player.x, player.y)
    player.inZeroG = (gMag < Player.GRAVITY_THRESHOLD)

    local gravityDirX, gravityDirY
    if gMag > 1e-6 then
        gravityDirX = gx / gMag
        gravityDirY = gy / gMag
        player.lastGravityX = gravityDirX
        player.lastGravityY = gravityDirY
    else
        gravityDirX = player.lastGravityX
        gravityDirY = player.lastGravityY
    end
    player.gravityX = gravityDirX
    player.gravityY = gravityDirY
    player.gravityMag = gMag

    local inputX, inputY = screenInput(cameraAngle)

    if player.rope.attached then
        updateRope(player, dt, asteroids)
    else
        updateRope(player, dt, asteroids)

        if player.inZeroG then
            local len = math.sqrt(inputX * inputX + inputY * inputY)
            if len > 0 then
                local nx = inputX / len
                local ny = inputY / len
                player.vx = player.vx + nx * Player.ZERO_G_SPEED * 4 * dt
                player.vy = player.vy + ny * Player.ZERO_G_SPEED * 4 * dt
            end

            player.vx = player.vx * (1 - 0.15 * dt)
            player.vy = player.vy * (1 - 0.15 * dt)

            local speed = math.sqrt(player.vx * player.vx + player.vy * player.vy)
            if speed > Player.ZERO_G_MAX_SPEED then
                player.vx = player.vx / speed * Player.ZERO_G_MAX_SPEED
                player.vy = player.vy / speed * Player.ZERO_G_MAX_SPEED
            end

            player.onGround = false
        else
            local onSurface = player.onGround or (player.groundMemory > 0)

            if onSurface and inputX ~= 0 then
                player.vx = player.vx + inputX * Player.SPEED * Player.GROUND_ACCEL * dt
                player.vy = player.vy + inputY * Player.SPEED * Player.GROUND_ACCEL * dt
            elseif not onSurface and (inputX ~= 0 or inputY ~= 0) then
                local len = math.sqrt(inputX * inputX + inputY * inputY)
                local nx = inputX / len
                local ny = inputY / len
                player.vx = player.vx + nx * Player.SPEED * Player.GROUND_ACCEL * Player.AIR_CONTROL * dt
                player.vy = player.vy + ny * Player.SPEED * Player.GROUND_ACCEL * Player.AIR_CONTROL * dt
            end

            if player.onGround then
                player.coyoteTimer = Player.COYOTE_TIME
            elseif player.coyoteTimer > 0 then
                player.coyoteTimer = player.coyoteTimer - dt
            end

            local jumpPressed = love.keyboard.isDown("space")
            if jumpPressed and player.jumpTimer <= 0
               and (player.onGround or player.coyoteTimer > 0) then
                local gFactor = math.sqrt(math.max(20, gMag) / Player.GRAVITY_BASE)
                local jumpImpulse = Player.JUMP_IMPULSE_BASE * gFactor
                player.vx = player.vx - gravityDirX * jumpImpulse
                player.vy = player.vy - gravityDirY * jumpImpulse
                player.jumpTimer = Player.JUMP_COOLDOWN
                player.onGround = false
                player.coyoteTimer = 0
                player.groundMemory = 0
            end

            player.vx = player.vx + gx * dt
            player.vy = player.vy + gy * dt

            local speed = math.sqrt(player.vx * player.vx + player.vy * player.vy)
            local maxSpeed = Player.SPEED * 2.5
            if speed > maxSpeed then
                player.vx = player.vx / speed * maxSpeed
                player.vy = player.vy / speed * maxSpeed
            end
        end
    end

    Player.resolveCollisions(player, dt, asteroids, gravityDirX, gravityDirY)

    if not player.inZeroG and player.onGround then
        local targetAngle = math.atan2(player.groundNormalY, player.groundNormalX) - math.pi * 0.5
        local diff = targetAngle - player.angle
        while diff > math.pi do diff = diff - math.pi * 2 end
        while diff < -math.pi do diff = diff + math.pi * 2 end
        player.angle = player.angle + diff * math.min(1, dt * 12)
    end
end

function Player.resolveCollisions(player, dt, asteroids, gravityDirX, gravityDirY)
    local totalDX = player.vx * dt
    local totalDY = player.vy * dt
    local totalLen = math.sqrt(totalDX * totalDX + totalDY * totalDY)
    local maxStep = Player.RADIUS * 0.4
    local steps = math.max(1, math.ceil(totalLen / maxStep))
    local stepDX = totalDX / steps
    local stepDY = totalDY / steps

    local groundNormalX, groundNormalY = 0, 0
    local bestGroundOverlap = 0

    for step = 1, steps do
        local px = player.x + stepDX
        local py = player.y + stepDY

        local iterations = 0
        local anyHit = true
        while anyHit and iterations < 8 do
            anyHit = false
            iterations = iterations + 1

            for _, ast in ipairs(asteroids) do
                local hit, pushX, pushY = Asteroid.circleCollides(ast, px, py, Player.RADIUS)
                if hit then
                    px = px + pushX
                    py = py + pushY

                    local plen = math.sqrt(pushX * pushX + pushY * pushY)
                    if plen > 1e-6 then
                        local nrmX = pushX / plen
                        local nrmY = pushY / plen

                        local dotWithGravity = nrmX * gravityDirX + nrmY * gravityDirY
                        local isGround = (dotWithGravity < GROUND_DOT_MAX)

                        if isGround then
                            if plen > bestGroundOverlap then
                                bestGroundOverlap = plen
                                groundNormalX = nrmX
                                groundNormalY = nrmY
                            end
                        end

                        local vn = player.vx * nrmX + player.vy * nrmY
                        if vn < 0 then
                            player.vx = player.vx - nrmX * vn
                            player.vy = player.vy - nrmY * vn
                        end
                        local vtx = player.vx - (player.vx * nrmX + player.vy * nrmY) * nrmX
                        local vty = player.vy - (player.vx * nrmX + player.vy * nrmY) * nrmY

                        local friction
                        if isGround then
                            friction = 0.15
                        else
                            friction = 0.02
                        end
                        player.vx = player.vx - vtx * friction
                        player.vy = player.vy - vty * friction
                    end

                    anyHit = true
                end
            end
        end

        player.x = px
        player.y = py
    end

    if bestGroundOverlap > 0 then
        player.onGround = true
        player.landed = true
        player.groundNormalX = groundNormalX
        player.groundNormalY = groundNormalY
        player.groundMemory = GROUND_MEMORY
    else
        player.onGround = false
    end

    player.wasOnGround = player.onGround
end

return Player


