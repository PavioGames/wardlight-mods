-- Relevo natural: remodels a new world's terrain after the game makes it,
-- inspired by how real land is shaped: a coast or an island, mountain
-- ranges along the coast, valleys carved by erosion, rivers that join on
-- their way down to the sea, and lakes where the water is held.
--
-- The game keeps its own limits (docs/limites-mods-terreno.md): the world
-- is 128, 256 or 384 blocks wide, 48 tall, with the sea at 15, and a mod
-- only changes blocks after the game has made them. So the script:
--
--   1. reads the ground the game made (and what stands on it: beacons,
--      ruins and the Light are never touched, and the land eases back to
--      them),
--   2. works out a new terrain on a coarse grid (noise, then erosion and
--      the rivers' paths, all from one seed),
--   3. rebuilds the world column by column, nearest the player first,
--      while the player waits up in the air, then lets them go and carries
--      on with the rest.
--
-- All of it runs a little each frame (a coroutine that yields), so no
-- frame is long and the game's limit per call is never reached. Only a
-- new world is changed: a world already played without this mod is left
-- alone. What was done is kept in the world itself, in a few blocks at the
-- bottom corner (y = 1), since a script cannot keep anything in the save.

local SEA = 15          -- the game's sea level (WATER_LEVEL)
local TOP = 47          -- the highest block a script may set
local PEAK = 44         -- no ground above this
local FLOOR = 3         -- no ground below this (y = 1 holds the marker)
local BUSY = 9000       -- work per frame while the player waits (a column is ~25)
local LIGHT = 900       -- and once they play: the rest of the world, gently
local HOLD = 40         -- blocks around the player made before they go

-- ---------------------------------------------------------------------
-- Small tools

local floor, sqrt, abs, min, max = math.floor, math.sqrt, math.abs, math.min, math.max
local get, put = blocks.get_block, blocks.set_block

local work_done, budget = 0, BUSY
local function work(n)
    work_done = work_done + n
    if work_done >= budget then
        work_done = 0
        coroutine.yield()
    end
end

local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function smooth(a, b, v) local t = clamp((v - a) / (b - a), 0, 1) return t * t * (3 - 2 * t) end

local seed = 0
local function hash(x, z, s)
    local h = (x * 374761393 + z * 668265263 + (s + seed) * 2246822519) & 0xffffffff
    h = ((h ~ (h >> 13)) * 1274126177) & 0xffffffff
    return h ~ (h >> 16)
end
local function rnd(x, z, s) return hash(x, z, s) / 4294967296.0 end

local function noise(x, z, s)
    local xi, zi = floor(x), floor(z)
    local fx, fz = x - xi, z - zi
    fx, fz = fx * fx * (3 - 2 * fx), fz * fz * (3 - 2 * fz)
    local a, b = rnd(xi, zi, s), rnd(xi + 1, zi, s)
    local c, d = rnd(xi, zi + 1, s), rnd(xi + 1, zi + 1, s)
    local top, bottom = a + (b - a) * fx, c + (d - c) * fx
    return top + (bottom - top) * fz
end

local function fbm(x, z, s, octaves)
    local sum, amp, total = 0, 1, 0
    for o = 1, octaves do
        sum = sum + noise(x, z, s + o * 31) * amp
        total = total + amp
        amp, x, z = amp * 0.5, x * 2.03, z * 2.03
    end
    return sum / total
end

-- Sharp crests where the noise crosses its middle: mountain ranges.
local function ridges(x, z, s, octaves)
    local sum, amp, total = 0, 1, 0
    for o = 1, octaves do
        local n = 1 - abs(noise(x, z, s + o * 57) * 2 - 1)
        sum = sum + n * n * amp
        total = total + amp
        amp, x, z = amp * 0.5, x * 2.1, z * 2.1
    end
    return sum / total
end

-- What the game makes on its own and the script may reshape; anything
-- else (a beacon, a ruin, the Light, a player's building) is left alone.
local NATURAL = {air = true, grass = true, dirt = true, stone = true, sand = true, wood = true,
                 leaves = true, water = true, coal_stone = true, lume = true}
local ROCK = {stone = true, coal_stone = true, lume = true}
local TREE = {wood = true, leaves = true}

-- ---------------------------------------------------------------------
-- The marker: x = 0..24, y = 1, z = 0. Four blocks that say "this mod
-- was here", twenty bits of seed, and one for "done".

local MAGIC = {"sand", "dirt", "sand", "dirt"}

local function marker_read()
    for k = 1, 4 do
        if get(k - 1, 1, 0) ~= MAGIC[k] then return nil end
    end
    local s = 0
    for b = 0, 19 do
        if get(4 + b, 1, 0) == "dirt" then s = s | (1 << b) end
    end
    return s, get(24, 1, 0) == "dirt"
end

local function marker_write(s)
    for k = 1, 4 do put(k - 1, 1, 0, MAGIC[k]) end
    for b = 0, 19 do put(4 + b, 1, 0, (s >> b) & 1 == 1 and "dirt" or "stone") end
    put(24, 1, 0, "stone")
end

-- ---------------------------------------------------------------------
-- State

local W            -- the world's side, in blocks
-- One number per column (index z * W + x), so that a 384 x 384 world
-- fits the 32 MB a script may use. Its bits:
--    0-5   the top of the ground the game made
--    6-11  the highest wood or leaves the game put there (0: none)
--   12     something built stands there
--   13-18  the new ground's top
--   19-24  the water's surface over it (0: none)
--   25-30  the top block (TOPS), + 4 if no tree may grow there; while the
--          terrain is being worked out, the ground before the rivers
local D = {}
local TOPS = {[0] = "grass", "sand", "stone", "dirt"}
local SUBS = {[0] = "dirt", "sand", "stone", "dirt"}

local function old_of(i) return D[i] & 63 end
local function tree_of(i) return (D[i] >> 6) & 63 end
local function built_at(i) return (D[i] >> 12) & 1 == 1 end
local function H_of(i) return (D[i] >> 13) & 63 end
local function LV_of(i) return (D[i] >> 19) & 63 end
local function M_of(i) return (D[i] >> 25) & 63 end
local function set_T(i, h, l) D[i] = (D[i] & ~(4095 << 13)) | (h << 13) | (l << 19) end
local function set_M(i, m) D[i] = (D[i] & ((1 << 25) - 1)) | (m << 25) end

local holding, hold_x, hold_z = false, 0, 0
local start_x, start_z = 0, 0
local progress, said_at, clock = 0, 0, 0
local finished = false
local job

local function say(text) blocks.say("Relevo natural: " .. text) end

local function hold_player(on)
    holding = on
    blocks.set("walk", on and 0 or 1)
    blocks.set("jump", on and 0 or 1)
    blocks.set("hunger", on and 0 or 1)
    blocks.set("cold", on and 0 or 1)
end

-- ---------------------------------------------------------------------
-- 1. Reading what the game made

local function scan()
    for z = 0, W - 1 do
        for x = 0, W - 1 do
            local i = z * W + x
            local y, tree, mark = TOP, 0, 0
            local b = get(x, y, z)
            while y > 1 and (b == "air" or TREE[b]) do
                if tree == 0 and TREE[b] then tree = y end
                y = y - 1
                b = get(x, y, z)
            end
            if not NATURAL[b] then mark = 1 end
            D[i] = y | (tree << 6) | (mark << 12)
            work(TOP - y + 2)
        end
    end
end

-- ---------------------------------------------------------------------
-- 2. The coarse terrain: shape, erosion, rivers and lakes

local G = 64       -- the coarse grid's side
local C            -- blocks per coarse cell
local ch = {}      -- height of each coarse cell (blocks)
local fill = {}    -- the height water would fill it to
local rcv = {}     -- the cell its water runs to (itself at the sea)
local area = {}    -- how many cells drain through it
local order = {}   -- cells from the sea upward

local DX = {1, -1, 0, 0, 1, 1, -1, -1}
local DZ = {0, 0, 1, -1, 1, -1, 1, -1}
local DD = {1, 1, 1, 1, 1.4142, 1.4142, 1.4142, 1.4142}

local function shape()
    local style = rnd(1, 2, 3) < 0.7 and "coast" or "island"
    local angle = rnd(4, 5, 6) * math.pi * 2
    local ca, sa = math.cos(angle), math.sin(angle)
    for gz = 0, G - 1 do
        for gx = 0, G - 1 do
            local u, v = (gx + 0.5) / G, (gz + 0.5) / G
            local across = (u - 0.5) * ca + (v - 0.5) * sa   -- toward inland
            local along = -(u - 0.5) * sa + (v - 0.5) * ca
            local land, range
            if style == "coast" then
                land = across * 1.9 + (fbm(u * 3, v * 3, 10, 4) - 0.5) * 1.1 + 0.25
                -- ranges run along the coast, as they often do
                local wx = (fbm(u * 2, v * 2, 20, 2) - 0.5) * 0.6
                range = ridges((across + wx) * 6 + 7, along * 2.2 + 7, 30, 4)
            else
                local r = sqrt((u - 0.5) ^ 2 + (v - 0.5) ^ 2) * 2
                land = 0.85 - r * 1.35 + (fbm(u * 3, v * 3, 10, 4) - 0.5) * 1.1
                local wx = (fbm(u * 2, v * 2, 20, 2) - 0.5) * 0.8
                range = ridges(u * 3.5 + wx + 7, v * 3.5 - wx + 7, 30, 4)
            end
            local h
            if land < 0 then
                h = SEA - 1.5 + land * 22
            else
                local inland = clamp(land, 0, 1)
                local hills = fbm(u * 6, v * 6, 40, 3)
                h = SEA + 1 + inland * 9 + (hills - 0.4) * 6 * inland
                h = h + smooth(0.15, 0.7, inland) * range ^ 1.5 * 30
            end
            ch[gz * G + gx] = clamp(h, FLOOR + 1, PEAK)
            work(45)
        end
    end
end

-- A binary heap of cells by height, for the flood below.
local hk, hv, hn = {}, {}, 0
local function push(k, v)
    hn = hn + 1
    local j = hn
    while j > 1 do
        local p = j >> 1
        if hk[p] <= k then break end
        hk[j], hv[j] = hk[p], hv[p]
        j = p
    end
    hk[j], hv[j] = k, v
end
local function pop()
    local k, v = hk[1], hv[1]
    local lk, lv = hk[hn], hv[hn]
    hk[hn], hv[hn] = nil, nil
    hn = hn - 1
    local j = 1
    while true do
        local c = j * 2
        if c > hn then break end
        if c < hn and hk[c + 1] < hk[c] then c = c + 1 end
        if hk[c] >= lk then break end
        hk[j], hv[j] = hk[c], hv[c]
        j = c
    end
    if hn > 0 then hk[j], hv[j] = lk, lv end
    return k, v
end

-- Floods the land from the sea upward: each cell learns where its water
-- goes (rcv), how high water would stand on it (fill: above its ground in
-- a hollow, a lake) and the order from the sea up (order).
local function flood()
    local seen = {}
    hn = 0
    local n = 0
    for i = 0, G * G - 1 do
        local gx, gz = i % G, i // G
        -- the sea takes the water, and so does the world's edge: what is
        -- beyond it is not there, but a river may well run on past it
        if ch[i] <= SEA or gx == 0 or gz == 0 or gx == G - 1 or gz == G - 1 then
            seen[i] = true
            fill[i], rcv[i] = ch[i], i
            push(ch[i], i)
        end
    end
    while hn > 0 do
        local f, c = pop()
        n = n + 1
        order[n] = c
        local cx, cz = c % G, c // G
        for k = 1, 8 do
            local nx, nz = cx + DX[k], cz + DZ[k]
            if nx >= 0 and nz >= 0 and nx < G and nz < G then
                local j = nz * G + nx
                if not seen[j] then
                    seen[j] = true
                    local fj = ch[j]
                    if fj < f + 0.001 then fj = f + 0.001 end
                    fill[j], rcv[j] = fj, c
                    push(fj, j)
                end
            end
        end
        work(12)
    end
    for k = 1, n do area[order[k]] = 1 end
    for k = n, 1, -1 do
        local c = order[k]
        local r = rcv[c]
        if r ~= c then area[r] = area[r] + area[c] end
    end
    work(n // 8)
end

-- Rivers wear their beds down, more the more water runs through them
-- (stream power, solved from the sea up so it stays steady), and slopes
-- creep (a little diffusion).
local function erode(rounds)
    for round = 1, rounds do
        flood()
        for k = 1, #order do
            local c = order[k]
            local r = rcv[c]
            if r ~= c and ch[c] > SEA and ch[c] > ch[r] then
                local cx, cz, rx, rz = c % G, c // G, r % G, r // G
                local dist = (cx ~= rx and cz ~= rz) and 1.4142 or 1
                local f = 0.014 * area[c] ^ 0.6 / dist
                ch[c] = (ch[c] + f * ch[r]) / (1 + f)
            end
        end
        work(#order)
        local new = {}
        for i = 0, G * G - 1 do
            local gx, gz = i % G, i // G
            local sum, n = 0, 0
            for k = 1, 4 do
                local nx, nz = gx + DX[k], gz + DZ[k]
                if nx >= 0 and nz >= 0 and nx < G and nz < G then
                    sum, n = sum + ch[nz * G + nx], n + 1
                end
            end
            local h = ch[i]
            new[i] = h > SEA and h + 0.08 * (sum / n - h) or h
        end
        ch = new
        work(G * G)
    end
    flood()
end

-- ---------------------------------------------------------------------
-- 3. The terrain block by block

local function coarse_at(t, x, z)
    local gx, gz = (x + 0.5) / C - 0.5, (z + 0.5) / C - 0.5
    gx, gz = clamp(gx, 0, G - 1.001), clamp(gz, 0, G - 1.001)
    local ix, iz = floor(gx), floor(gz)
    local fx, fz = gx - ix, gz - iz
    local i = iz * G + ix
    local a, b, c, d = t[i], t[i + 1], t[i + G], t[i + G + 1]
    local top, bottom = a + (b - a) * fx, c + (d - c) * fx
    return top + (bottom - top) * fz
end

-- Each cell's centre, nudged a little so rivers wind instead of running
-- along the grid.
local function centre(c)
    local cx, cz = c % G, c // G
    return (cx + 0.1 + rnd(cx, cz, 70) * 0.8) * C, (cz + 0.1 + rnd(cx, cz, 71) * 0.8) * C
end

local function terrain()
    -- the ground, from the coarse heights and some detail; a lake where the
    -- coarse flood found a hollow. M keeps this first ground for a while.
    for z = 0, W - 1 do
        for x = 0, W - 1 do
            local i = z * W + x
            local h = coarse_at(ch, x, z)
            local rough = 1 + 2.5 * smooth(26, 40, h)
            h = h + (fbm(x / 11, z / 11, 80, 3) - 0.5) * 2.4 * rough
            h = clamp(floor(h + 0.5), FLOOR, PEAK)
            local l = 0
            local c = clamp(z // C, 0, G - 1) * G + clamp(x // C, 0, G - 1)
            if fill[c] - ch[c] > 1 and ch[c] > SEA then
                local level = floor(fill[c])
                if h < level then l = level end
            end
            set_T(i, h, l)
            set_M(i, h)
            work(18)
        end
    end
    -- the rivers, drawn from each cell to the one its water runs to
    local least = max(12, G * G // 220)
    local widest = 1.2 + C * 0.35
    for c = 0, G * G - 1 do
        local r = rcv[c]
        if area[c] >= least and r ~= c and ch[c] > SEA - 1 then
            local strength = sqrt(area[c] / least)
            local half = min(0.5 + strength * 0.45, widest)
            local depth = min(1 + floor(strength / 1.5), 3)
            local ax, az = centre(c)
            local bx, bz = centre(r)
            local fa, fb = fill[c], fill[r]
            local steps = floor(sqrt((bx - ax) ^ 2 + (bz - az) ^ 2) * 2) + 1
            local reach = floor(half + 1)
            for s = 0, steps do
                local t = s / steps
                local px, pz = ax + (bx - ax) * t, az + (bz - az) * t
                -- the water's surface: where the flood says, but never above
                -- the ground it runs through
                local gx, gz = clamp(floor(px), 0, W - 1), clamp(floor(pz), 0, W - 1)
                local level = max(min(floor(fa + (fb - fa) * t), M_of(gz * W + gx) - 1), SEA)
                for z = floor(pz) - reach, floor(pz) + reach do
                    for x = floor(px) - reach, floor(px) + reach do
                        if x >= 0 and z >= 0 and x < W and z < W then
                            local i = z * W + x
                            local d = sqrt((x + 0.5 - px) ^ 2 + (z + 0.5 - pz) ^ 2)
                            if d <= half then
                                local bed = level - depth + (d > half - 0.7 and 1 or 0)
                                if bed >= level then bed = level - 1 end
                                local h, l = H_of(i), LV_of(i)
                                if l == 0 or l > level then
                                    set_T(i, min(h, bed), level)
                                elseif l == level then
                                    set_T(i, min(h, bed), l)
                                end
                            end
                        end
                    end
                end
                work(4 * (2 * reach + 1) ^ 2)
            end
        end
    end
    -- the sea, wherever the ground is below it
    for i = 0, W * W - 1 do
        local h, l = H_of(i), LV_of(i)
        if h < SEA and l < SEA then set_T(i, h, SEA) end
        if i % 64 == 0 then work(40) end
    end
end

-- Ease the new ground back to the old one near anything built, so a
-- beacon or a ruin keeps standing where the game put it, and near the
-- start, where the game puts players back after fainting.
local function blend()
    local dist = {}
    local queue, head, tail = {}, 1, 0
    for i = 0, W * W - 1 do
        if built_at(i) then
            dist[i] = 0
            tail = tail + 1
            queue[tail] = i
        end
        if i % 64 == 0 then work(30) end
    end
    local si = start_z * W + start_x
    if not dist[si] then
        dist[si] = 0
        tail = tail + 1
        queue[tail] = si
    end
    while head <= tail do
        local i = queue[head]
        head = head + 1
        local d = dist[i]
        if d < 14 then
            local x, z = i % W, i // W
            for k = 1, 8 do
                local nx, nz = x + DX[k], z + DZ[k]
                if nx >= 0 and nz >= 0 and nx < W and nz < W then
                    local j = nz * W + nx
                    if not dist[j] then
                        dist[j] = d + 1
                        tail = tail + 1
                        queue[tail] = j
                    end
                end
            end
        end
        local w = smooth(3, 13, d)
        local o = old_of(i)
        local h = floor(o + (H_of(i) - o) * w + 0.5)
        local l = LV_of(i)
        if w < 1 then l = h < SEA and SEA or 0 end
        set_T(i, h, l)
        work(8)
    end
end

-- Water never stands against air: where a column of water meets dry ground
-- lower than its surface, the ground rises to hold it.
local function banks()
    for pass = 1, 2 do
        for z = 0, W - 1 do
            for x = 0, W - 1 do
                local i = z * W + x
                local l = LV_of(i)
                if l > H_of(i) then
                    for k = 1, 4 do
                        local nx, nz = x + DX[k], z + DZ[k]
                        if nx >= 0 and nz >= 0 and nx < W and nz < W then
                            local j = nz * W + nx
                            local hj, lj = H_of(j), LV_of(j)
                            if lj <= hj and hj < l then set_T(j, l, lj) end
                        end
                    end
                end
            end
            work(W * 2)
        end
    end
end

-- Which block goes on top: sand by the water, bare stone where it is
-- steep or high, grass elsewhere; under water, sand, or stone deep down.
-- No tree within three blocks of water.
local function surfaces()
    -- near[i]: how far the nearest water is (1 to 4) + 8 * its surface,
    -- spread from the dry ground right beside water (not from all of the
    -- sea, which would not fit in memory)
    local near = {}
    local queue, head, tail = {}, 1, 0
    for z = 0, W - 1 do
        for x = 0, W - 1 do
            local i = z * W + x
            local h, l = H_of(i), LV_of(i)
            if l <= h then
                for k = 1, 4 do
                    local nx, nz = x + DX[k], z + DZ[k]
                    if nx >= 0 and nz >= 0 and nx < W and nz < W then
                        local j = nz * W + nx
                        local lj = LV_of(j)
                        if lj > H_of(j) and (not near[i] or lj > near[i] >> 3) then near[i] = 8 * lj + 1 end
                    end
                end
                if near[i] then
                    tail = tail + 1
                    queue[tail] = i
                end
            end
        end
        work(W * 3)
    end
    while head <= tail do
        local i = queue[head]
        head = head + 1
        local d = near[i] & 7
        if d < 4 then
            local x, z = i % W, i // W
            for k = 1, 4 do
                local nx, nz = x + DX[k], z + DZ[k]
                if nx >= 0 and nz >= 0 and nx < W and nz < W then
                    local j = nz * W + nx
                    if not near[j] and LV_of(j) <= H_of(j) then
                        near[j] = (near[i] & ~7) + d + 1
                        tail = tail + 1
                        queue[tail] = j
                    end
                end
            end
        end
        work(4)
    end
    queue = nil
    for z = 0, W - 1 do
        for x = 0, W - 1 do
            local i = z * W + x
            local h, l = H_of(i), LV_of(i)
            local steep = 0
            for k = 1, 4 do
                local nx, nz = x + DX[k], z + DZ[k]
                if nx >= 0 and nz >= 0 and nx < W and nz < W then
                    steep = max(steep, abs(H_of(nz * W + nx) - h))
                end
            end
            local top = 0 -- grass
            local nd, nl = 9, 0
            if l > h then nd = 0 elseif near[i] then nd, nl = near[i] & 7, near[i] >> 3 end
            if l > h then
                if l - h > 5 and noise(x / 7, z / 7, 90) > 0.45 then top = 2
                elseif l > SEA and noise(x / 5, z / 5, 91) > 0.6 then top = 3
                else top = 1 end
            elseif nd <= 2 and h <= nl + 1 then
                top = 1
            elseif steep >= 3 or h >= 37 + noise(x / 6, z / 6, 92) * 5 then
                top = 2
            end
            set_M(i, top + (nd <= 3 and 4 or 0))
            work(16)
        end
    end
end

-- ---------------------------------------------------------------------
-- 4. Building it

local function remodel(x, z)
    local i = z * W + x
    if built_at(i) then return end
    local h, l, o = H_of(i), LV_of(i), old_of(i)
    local m = M_of(i) & 3
    local top, sub = TOPS[m], SUBS[m]
    local from = max(o, h, l, tree_of(i))
    local to = max(min(o, h) - 4, 2)
    local want = {}
    for y = from, to, -1 do
        local b = get(x, y, z)
        if not NATURAL[b] then return end -- something was built here since
        local w
        if y > h then
            w = y <= l and "water" or "air"
        elseif y == h then
            w = top
        elseif y >= h - 3 then
            w = (sub == "dirt" and y < h - 2) and "stone" or sub
        elseif ROCK[b] or (b == "air" and y < o - 1) then
            w = b
        else
            w = "stone"
        end
        if w ~= b then want[y] = w end
    end
    for y, w in pairs(want) do put(x, y, z, w) end
    work(from - to + 4)
end

local function plant(x, z)
    local i = z * W + x
    if M_of(i) ~= 0 or built_at(i) then return end -- grass, away from water
    local h = H_of(i)
    if LV_of(i) > h then return end
    local chance = h < 22 and 1 / 34 or h < 34 and 1 / 16 or 1 / 70
    if noise(x / 23, z / 23, 95) < 0.35 then chance = chance / 4 end -- clearings
    if rnd(x, z, 96) >= chance then return end
    for k = 1, 4 do
        if abs(H_of((z + DZ[k]) * W + x + DX[k]) - h) > 1 then return end
    end
    local tall = 4 + floor(rnd(x, z, 97) * 3)
    if h + tall + 2 > TOP then return end
    for dy = -2, 2 do
        for dx = -2, 2 do
            for dz = -2, 2 do
                local y = h + tall + dy
                local r = abs(dx) + abs(dz) + (dy > 0 and dy * 2 or 0)
                if r < 3 or (r == 3 and rnd(x + dx, z + dz, 98 + y) < 0.5) then
                    if get(x + dx, y, z + dz) == "air" then put(x + dx, y, z + dz, "leaves") end
                end
            end
        end
    end
    for dy = 1, tall do put(x, h + dy, z, "wood") end
    work(40)
end

local function build_chunk(cx, cz)
    for z = cz * 16, cz * 16 + 15 do
        for x = cx * 16, cx * 16 + 15 do
            remodel(x, z)
        end
        if holding then blocks.teleport(hold_x + 0.5, 46, hold_z + 0.5) end
    end
    -- trees only 2 blocks in from the chunk's edge: their leaves stay in it,
    -- so the next chunk's rebuild never cuts one in half
    for z = cz * 16 + 2, cz * 16 + 13 do
        for x = cx * 16 + 2, cx * 16 + 13 do
            plant(x, z)
        end
        work(4)
    end
end

-- Dry ground near (x, z), for the player to land on.
local function landing(x, z)
    for r = 0, W do
        for dz = -r, r do
            for dx = -r, r do
                if max(abs(dx), abs(dz)) == r then
                    local px, pz = x + dx, z + dz
                    if px >= 0 and pz >= 0 and px < W and pz < W then
                        local i = pz * W + px
                        if LV_of(i) <= H_of(i) then
                            local y = TOP
                            while y > 1 and get(px, y, pz) == "air" do y = y - 1 end
                            local b = get(px, y, pz)
                            if b ~= "water" and b ~= "leaves" and get(px, y + 1, pz) == "air" and get(px, y + 2, pz) == "air" then
                                return px, y + 1, pz
                            end
                        end
                    end
                end
            end
        end
    end
    return x, TOP, z
end

local function release()
    local x, y, z = landing(start_x, start_z)
    hold_player(false)
    budget = LIGHT
    blocks.teleport(x + 0.5, y, z + 0.5)
end

-- ---------------------------------------------------------------------
-- The whole job

local function run()
    say("lendo o mundo... / reading the world...")
    scan()
    progress = 0.15
    local s = marker_read()
    if not s then
        s = 0
        for i = 0, W * W - 1, 37 do s = (s * 31 + old_of(i) + i) % 1048576 end
        marker_write(s)
    end
    seed = s
    C = W / G
    shape()
    progress = 0.2
    erode(10)
    progress = 0.3
    terrain()
    ch, fill, rcv, area, order = nil, nil, nil, nil, nil
    blend()
    banks()
    surfaces()
    progress = 0.4
    -- chunks nearest the player first
    local chunks = {}
    local n = W // 16
    local pcx, pcz = hold_x // 16, hold_z // 16
    for cz = 0, n - 1 do
        for cx = 0, n - 1 do
            chunks[#chunks + 1] = {cx, cz, (cx - pcx) ^ 2 + (cz - pcz) ^ 2}
        end
    end
    table.sort(chunks, function(a, b) return a[3] < b[3] end)
    local near = (HOLD / 16 + 0.8) ^ 2
    for k, c in ipairs(chunks) do
        if holding and c[3] > near then
            release()
            say("pode andar; o resto do mundo continua sendo feito. / you may go; the rest is still being made.")
        end
        build_chunk(c[1], c[2])
        progress = 0.4 + 0.6 * k / #chunks
    end
    if holding then release() end
    put(24, 1, 0, "dirt") -- done
    say("pronto! / done!")
end

function on_start()
    -- the world's side: y = 0 is stone inside the world, air outside it
    W = 128
    while W < 384 and get(W, 0, 0) == "stone" do W = W + 128 end
    local s, done = marker_read()
    if done then
        finished = true
        return
    end
    if not s and blocks.day() > 0 then
        -- a world already played: never reshaped under someone's feet
        say("só muda mundos novos; este fica como está. / only reshapes new worlds; this one stays as it is.")
        finished = true
        return
    end
    local x, _, z = blocks.player()
    hold_x, hold_z = clamp(floor(x), 0, W - 1), clamp(floor(z), 0, W - 1)
    start_x, start_z = hold_x, hold_z
    hold_player(true)
    job = coroutine.create(run)
end

function on_tick(dt)
    if finished or not job then return end
    clock = clock + dt
    if holding then blocks.teleport(hold_x + 0.5, 46, hold_z + 0.5) end
    local ok, err = coroutine.resume(job)
    if not ok then
        finished = true
        if holding then hold_player(false) end
        say("erro / error: " .. tostring(err))
        return
    end
    if coroutine.status(job) == "dead" then
        finished = true
        if holding then hold_player(false) end
        return
    end
    if clock - said_at >= 3 then
        said_at = clock
        say(floor(progress * 100) .. "%")
    end
end
