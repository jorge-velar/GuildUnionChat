-- Guild Union - modo combate: en combate dentro de una banda o mazmorra el addon solo muestra y manda [+ARCHITECTURE.md]
local _, HU = ...

-- (campos de batalla y arenas también: ahí el juego bloquea los envíos en combate y, sin este modo, la
-- cola se llenaba de saludos que caducaban y se perdía el contacto con las otras hermandades. 11/11)
local INSTANCE_KINDS = { party = true, raid = true, pvp = true, arena = true }
local PVP_KINDS = { pvp = true, arena = true }
local CEDE_PENALTY = 150         -- (lo mismo que resta Busy() en banda: Comm.lua)
local CEDE_IN_DUNGEON = true     -- (en banda ya lo resta Busy(); esto lo añade en mazmorra)
local DRAIN_MS = 0.8             -- trabajo por fotograma al salir de combate
local REQ_MAX_AGE = 15           -- una petición más vieja que esto ya la ha contestado otro
local RB_SETS_PER_TAG = 2        -- listas enteras guardadas por hermandad (las dos últimas)
local RC_PER_TAG = 40
local DATA_PER_CMD = { HL = 300 }
local DATA_DEFAULT = 60
local INBOX_MAX = 2000
local ENC_MAX = 900              -- (por si no llega el fin del encuentro)

-- lo que llega y se aplaza: "list" = listas de conectados, "data" = datos, "req" = peticiones [+ARCHITECTURE.md]
local DEFER_IN = {
    RB = "list",
    RF = "req", NQ = "req", HQ = "req", OQ = "req", FQ = "req", WQ = "req",
    HL = "data", PB = "data", OD = "data", OE = "data", WH = "data", WL = "data", WD = "data",
    -- (quién es el enlace o los ayudantes de otra hermandad, contado por mi hermandad: vale el último)
    PH = "last", PL = "last",
}
local BULK_PREFIX = { RB = true, RC = true, PB = true, OD = true, WL = true, HL = true }

local clock = debugprofilestop or function() return GetTime() * 1000 end
local inInst, instKind, regen, enc, encT = false, nil, false, false, 0
local hold, draining = false, false
HU.combatDiag = { holds = 0, stored = 0, dropped = 0, replayed = 0, actions = 0 }
local diag = HU.combatDiag

function HU:CombatHold() return hold end

---------------------------------------------------------------------------
-- Lo que llega
---------------------------------------------------------------------------
local inbox, inboxN, nextI = {}, 0, 0
local rbSets, rcList, dataN, reqKey, rawSeen = {}, {}, {}, {}, {}

local function Kill(e)
    if e.dead then return end
    e.dead = true
    inboxN = inboxN - 1
    if e.raw then rawSeen[e.raw] = nil end
end
local function Push(e)
    if inboxN >= INBOX_MAX then diag.dropped = diag.dropped + 1 return false end
    nextI = nextI + 1
    e.i, e.t = nextI, GetTime()
    inbox[#inbox + 1] = e
    inboxN = inboxN + 1
    rawSeen[e.raw] = true
    diag.stored = diag.stored + 1
    return true
end

local function Store(cmd, sender, f, dist, raw)
    if rawSeen[raw] then return end -- (la misma copia por otra vía o de otro ayudante)
    local kind = DEFER_IN[cmd]
    local e = { cmd = cmd, sender = sender, dist = dist, raw = raw }
    if kind == "list" then
        local tag = f[1] or ""
        if cmd == "RB" then
            -- (una lista entera = todos sus trozos; se guardan las dos últimas de cada hermandad)
            -- (número de serie, origen y huella: RB~ETIQ~seq~total~conect~parte~partes~datos~edad~origen~estado~huella)
            local id = tostring(f[2]) .. "\1" .. tostring(f[9] or "") .. "\1" .. tostring(f[11] or "")
            local sets = rbSets[tag] or {}
            rbSets[tag] = sets
            local set
            for _, s in ipairs(sets) do if s.id == id then set = s end end
            if not set then
                set = { id = id, items = {} }
                sets[#sets + 1] = set
                if #sets > RB_SETS_PER_TAG then
                    for _, old in ipairs(table.remove(sets, 1).items) do Kill(old) end
                end
            end
            if Push(e) then set.items[#set.items + 1] = e end
        else
            local l = rcList[tag] or {}
            rcList[tag] = l
            if Push(e) then
                l[#l + 1] = e
                if #l > RC_PER_TAG then Kill(table.remove(l, 1)) end
            end
        end
    elseif kind == "req" or kind == "last" then
        -- (de cada uno, la última de cada tipo; las peticiones viejas se tiran al salir)
        local key = cmd .. "\1" .. sender:lower() .. "\1" .. tostring(f[1] or "") .. "\1" .. tostring(f[2] or "")
        if reqKey[key] then Kill(reqKey[key]) end
        if Push(e) then reqKey[key] = e end
    else
        local cap = DATA_PER_CMD[cmd] or DATA_DEFAULT
        local n = dataN[cmd] or 0
        if n >= cap then diag.dropped = diag.dropped + 1 return end
        if Push(e) then dataN[cmd] = n + 1 end
    end
end

-- lo que cuesta procesar cada orden (el más caro de los últimos, que va bajando poco a poco); se mide
-- siempre, también fuera de combate, para saber si una lista cabe en un fotograma de combate
local estBy = {}
for cmd in pairs(DEFER_IN) do
    local orig = HU.comm[cmd]
    if orig then
        HU.comm[cmd] = function(self, sender, f, dist, raw, ...)
            -- (lo del canal no se guarda: al repetirlo faltaría con qué canal llegó)
            if hold and not HU.combatReplay and dist ~= "CHANNEL" and type(raw) == "string" and sender then
                return Store(cmd, sender, f, dist, raw)
            end
            if cmd ~= "RB" then return orig(self, sender, f, dist, raw, ...) end
            local t0 = clock()
            orig(self, sender, f, dist, raw, ...)
            estBy.RB = math.max(clock() - t0, (estBy.RB or 0) * 0.9)
        end
    end
end

---------------------------------------------------------------------------
-- Lo que se manda o se calcula: en combate se apunta y se hace al salir (una vez cada cosa)
---------------------------------------------------------------------------
local actions, actionOrder = {}, {}
---------------------------------------------------------------------------
-- Al salir de combate: primero lo que llegó (en orden), luego lo apuntado; ≤DRAIN_MS por fotograma
---------------------------------------------------------------------------
local pos = 1
local function NextInbox()
    while inbox[pos] do
        local e = inbox[pos]
        pos = pos + 1
        if not e.dead then
            Kill(e)
            if DEFER_IN[e.cmd] ~= "req" or GetTime() - e.t <= REQ_MAX_AGE then return e end
        end
    end
    return nil
end
local function ResetInbox()
    wipe(inbox); wipe(rbSets); wipe(rcList); wipe(dataN); wipe(reqKey); wipe(rawSeen)
    inboxN, pos = 0, 1
end

-- (lo que cuesta un mensaje repetido: el más caro de los últimos, que va bajando poco a poco. Antes de
-- empezar otro en el mismo fotograma se mira si cabe; el primero de cada fotograma va siempre)
local est = 0.3
local function Replay(e)
    diag.replayed = diag.replayed + 1
    local raw = e.raw
    if e.cmd == "RB" then
        -- (la edad de la copia, con lo que ha esperado: si no, una lista de hace 5 min parecería
        -- recién hecha y pisaría a otra más nueva)
        local p = HU.Split(raw, "~")
        local age = tonumber(p[9])
        if age then p[9] = tostring(age + math.floor(GetTime() - e.t)); raw = table.concat(p, "~") end
    end
    local t0 = clock()
    HU.combatReplay = true
    -- (por la entrada normal: vuelve a pasar el tope por remitente y la seguridad de siempre)
    HU:SafeCall("combate", HU.OnAddonMessage, BULK_PREFIX[e.cmd] and HU.PREFIX_B or HU.PREFIX, raw, e.dist, e.sender)
    HU.combatReplay = nil
    local ms = clock() - t0
    est = math.max(ms, est * 0.9)
    if e.cmd ~= "RB" then estBy[e.cmd] = math.max(ms, (estBy[e.cmd] or 0) * 0.9) end -- (RB ya se mide dentro)
    if ms > (diag.maxReplay or 0) then diag.maxReplay, diag.maxReplayCmd = ms, e.cmd end
end

local holdDropped = 0
-- Volver a saludar: mi hermandad y, si soy el enlace, las otras. Como mucho una vez cada 20 s.
local helloT = -999
local function HelloAgain()
    if GetTime() - helloT < 20 or not HU.myTag or not HU.HelloCycle then return end
    helloT = GetTime()
    HU:SafeCall("combate", HU.HelloCycle, HU)
    if HU.AnnounceRelay then HU.After(1.5, function() HU:AnnounceRelay(true) end) end
end
local function CatchUp()
    -- (tras un combate largo o si se tiró algo: se piden a mi hermandad todas las listas de una vez; [+ARCHITECTURE.md]
    local long = diag.holdT and diag.releaseT and diag.releaseT - diag.holdT > 60
    if not (long or diag.dropped > holdDropped) then return end
    -- (y se saluda ya: los saludos de mientras tanto no salieron, y sin ellos nadie me contesta)
    HelloAgain()
    if HU.OtherTags and HU.myTag and HU.AskGuildForMissing then
        HU.rosterNeed = HU.rosterNeed or {}
        for _, tag in ipairs(HU:OtherTags()) do HU.rosterNeed[tag] = true end
        HU:SafeCall("combate", HU.AskGuildForMissing, HU)
    end
end

local function Drain()
    if hold then draining = false return end
    local t0 = clock()
    repeat
        local e = NextInbox()
        if e then
            Replay(e)
        else
            if pos > 1 then ResetInbox() end
            local key = table.remove(actionOrder, 1)
            if not key then
                draining = false
                diag.drainedT = GetTime()
                return CatchUp()
            end
            local a = actions[key]
            actions[key] = nil
            if a then
                diag.actions = diag.actions + 1
                local t1 = clock()
                HU:SafeCall("combate", a.run, HU, unpack(a.args, 1, a.args.n))
                local ms = clock() - t1
                if ms > (diag.maxAction or 0) then diag.maxAction, diag.maxActionName = ms, key:match("^[^\1]+") end
                -- (una tarea por fotograma: cada una ya reparte lo suyo en los siguientes)
                break
            end
        end
    until clock() - t0 + est >= DRAIN_MS
    HU.After(0, Drain)
end

local function StartDrain()
    if draining then return end
    draining = true
    diag.releaseT = GetTime()
    -- (mi hermandad, leída de nuevo: la lectura se dejó para después; con su freno de 15 s, que entre pulls
    -- se sale de combate cada pocos segundos)
    if HU.RequestRoster then HU:RequestRoster() end
    HU.After(0, Drain)
end

-- En combate largo: las listas enteras (RB) que llevan más de TRICKLE_AGE s guardadas se procesan igual, [+ARCHITECTURE.md]
local TRICKLE_AGE, TRICKLE_EVERY, TRICKLE_MS = 60, 0.1, 1.0
local trickling = false
local function Trickle()
    if not hold then trickling = false return end
    local now = GetTime()
    local cost = estBy.RB or 99 -- (sin medir aún: no se arriesga)
    if cost <= TRICKLE_MS then
        for i = pos, #inbox do
            local e = inbox[i]
            if now - e.t <= TRICKLE_AGE then break end
            if not e.dead and e.cmd == "RB" then
                Kill(e)
                diag.trickled = (diag.trickled or 0) + 1
                Replay(e)
                break
            end
        end
    end
    -- (si las listas salen caras en este ordenador, no se gotean: esperan a salir de combate. La estimación
    -- solo cambia con lo que se mide al procesarlas)
    HU.After(TRICKLE_EVERY, Trickle)
end

local function Update()
    if enc and GetTime() - encT > ENC_MAX then enc = false end
    local locked = InCombatLockdown and InCombatLockdown() or false
    -- (en un campo de batalla el bloqueo del chat puede durar algo más que el combate)
    if not locked and PVP_KINDS[instKind] and HU.IsChatLockedDown then locked = HU:IsChatLockedDown() end
    local now = inInst and (regen or enc or locked) or false
    if now == hold then return end
    hold = now
    if hold then
        diag.holds, diag.holdT = diag.holds + 1, GetTime()
        if PVP_KINDS[instKind] and not HU.pvpLockTold then
            -- (una vez por sesión: si no, quien no lo sabe cree que el addon se ha roto)
            HU.pvpLockTold = true
            HU:Print(HU.L("En combate dentro de un campo de batalla o una arena el juego bloquea el chat unido: no ves a las otras hermandades ni les llega lo que escribes. Vuelve solo al acabar el combate."))
        end
        holdDropped = diag.dropped
        if not trickling then trickling = true; HU.After(TRICKLE_EVERY, Trickle) end
    else
        StartDrain()
    end
end

---------------------------------------------------------------------------
-- Ceder el papel de enlace o ayudante en una instancia
---------------------------------------------------------------------------
-- En cola de un campo de batalla o una arena (o con la partida lista para entrar): se cede ya, cuando
-- todavía se puede avisar. Al entrar puede ser tarde: el juego bloquea los envíos (Jorge, 11/11)
local queued = false
local function InPvpQueue()
    if not GetBattlefieldStatus then return false end
    local n = (GetMaxBattlefieldID and tonumber(GetMaxBattlefieldID())) or 3
    for i = 1, n do
        local ok, status = pcall(GetBattlefieldStatus, i)
        -- («active» también: entre aceptar la partida y terminar de cargarla aún no cuenta como instancia)
        if ok and not HU.Secret(status) and (status == "queued" or status == "confirm" or status == "active") then return true end
    end
    return false
end

local origScore = HU.RelayScore
if origScore then
    HU.RelayScore = function(self)
        local s = origScore(self)
        if CEDE_IN_DUNGEON and inInst and instKind == "party" then s = s - CEDE_PENALTY end
        -- (dentro de la partida ya lo resta Busy(), en Comm.lua: aquí solo mientras se espera fuera)
        if queued and not inInst then s = s - CEDE_PENALTY end
        return s
    end
end

-- Al entrar: si reparto algo, lo digo ya a mi hermandad (con la puntuación nueva), sin esperar mi saludo
-- de dentro de 2-5 min
local function CedeNow()
    if not HU.myTag or not IsInGuild() or not HU.RosterSlot then return end
    if not HU:RosterSlot() then return end
    HU.myAdvScore = HU:RelayScore()
    if HU.ForgetRelayMemo then HU.ForgetRelayMemo() end
    -- (1,1 s: quién es el enlace se recuerda 1 s, MassLogin.lua)
    HU.After(1.1, function()
        if HU.myTag and IsInGuild() then HU:Send(HU:HelloText("HI"), "GUILD", nil, true) end
    end)
end

local function CheckQueue()
    local now = InPvpQueue()
    if now == queued then return end
    queued = now
    if queued then
        if not inInst then CedeNow() end
    elseif HU.myTag and HU.RelayScore then
        -- (ha salido de la cola sin entrar: la puntuación vuelve a la suya; se dirá en el saludo siguiente)
        HU.myAdvScore = HU:RelayScore()
        if HU.ForgetRelayMemo then HU.ForgetRelayMemo() end
    end
end
function HU:InPvpQueue() return queued end

local function InHelpers(k)
    for _, n in ipairs(HU.advertisedHelpers or {}) do if HU:Key(n) == k then return true end end
    return false
end

-- Lo que hace quien sigue fuera cuando el enlace o un ayudante dice que ha bajado su puntuación
for _, cmd in ipairs({ "HI", "HR" }) do
    local orig = HU.comm[cmd]
    if orig then
        HU.comm[cmd] = function(self, sender, f, dist, ...)
            local k = dist == "GUILD" and sender and sender:lower()
            local old = k and self.guildPeers[k]
            local oldScore = old and old.score
            local relayK = k and self.RelayName and self:Key(self:RelayName() or "")
            local r = orig(self, sender, f, dist, ...)
            local p = k and self.guildPeers[k]
            if not (p and oldScore and p.score and p.score <= oldScore - 100) then return r end
            if relayK == k then
                -- (se ha ido el enlace: si ahora lo soy yo, saludo y me presento a las otras hermandades ya)
                HU.After(1.1, function()
                    if not hold and HU:IsRelay() then
                        HU:SafeCall("hello", HU.HelloCycle, HU)
                        HU.After(1.5, function() HU:AnnounceRelay(true) end)
                    end
                end)
            elseif InHelpers(k) then
                -- (se ha ido un ayudante: elijo otros sin esperar los 2 min; lo que piden los ayudantes se
                -- recuerda 2 s, de ahí los 2,1 s)
                self.helpersChangedT = nil
                HU.After(2.1, function()
                    if HU:IsRelay() and HU.HelpersChangedHello then
                        HU:HelpersChangedHello(true)
                        HU.After(1, function() HU:AnnounceRelay(true) end)
                    end
                end)
            end
            return r
        end
    end
end

---------------------------------------------------------------------------
-- Eventos
---------------------------------------------------------------------------
local function CheckInstance()
    local was, wasKind = inInst, instKind
    local i, kind = false, nil
    if IsInInstance then i, kind = IsInInstance() end
    inInst = (i and INSTANCE_KINDS[kind]) and true or false
    instKind = inInst and kind or nil
    if inInst and not was then CedeNow() end
    -- (la hora a la que empezó la partida, para pedir al salir el chat que no se ha podido leer. Se
    -- guarda: un /reload dentro no la pierde ni la pone a cero)
    if inInst and PVP_KINDS[instKind] and HU.db and not HU.db.pvpSince then
        HU.db.pvpSince = HU.StampNow() - 30
    end
    Update()
    -- (al salir de un campo de batalla o una arena: ponerse al día enseguida, sin esperar al ciclo)
    if was and not inInst and PVP_KINDS[wasKind] then
        local since = HU.db and HU.db.pvpSince
        if HU.db then HU.db.pvpSince = nil end
        HU.After(3, function()
            if hold then return end
            if since and HU.AskMissedChat then
                local heard = HU.hlHeard or 0
                HU:AskMissedChat(since)
                -- (contesta uno solo de mi hermandad; si justo ese está en otra partida no llega nada:
                -- se repite una vez, cuando ya puede contestar otro)
                HU.After(150, function()
                    if not hold and (HU.hlHeard or 0) == heard then HU:AskMissedChat(since) end
                end)
            end
            HelloAgain()
            if HU.OtherTags and HU.myTag and HU.AskGuildForMissing then
                HU.rosterNeed = HU.rosterNeed or {}
                for _, tag in ipairs(HU:OtherTags()) do HU.rosterNeed[tag] = true end
                HU:SafeCall("combate", HU.AskGuildForMissing, HU)
            end
        end)
    end
end

HU:On("UPDATE_BATTLEFIELD_STATUS", CheckQueue)
HU:On("PLAYER_ENTERING_WORLD", CheckQueue)
HU:On("PLAYER_ENTERING_WORLD", CheckInstance)
HU:On("ZONE_CHANGED_NEW_AREA", CheckInstance)
HU:On("PLAYER_REGEN_DISABLED", function() regen = true; Update() end)
HU:On("PLAYER_REGEN_ENABLED", function() regen = false; Update() end)
-- (si el juego no tiene estos eventos, HU:On no los registra y no pasa nada)
HU:On("ENCOUNTER_START", function() enc, encT = true, GetTime(); Update() end)
HU:On("ENCOUNTER_END", function() enc = false; Update() end)
HU:OnStart(function()
    CheckInstance()
    -- (entro fuera de una partida con la hora de una vieja guardada, p. ej. tras caerse el juego dentro:
    -- ya se pide lo de «mientras no estabas» al arrancar, Social.lua)
    if not (inInst and PVP_KINDS[instKind]) and HU.db then HU.db.pvpSince = nil end
    -- (red de seguridad: si se pierde el aviso de fin de combate, no se queda en pausa)
    HU.NewTicker(5, function()
        if not hold then return end
        if regen and InCombatLockdown and not InCombatLockdown() then regen = false end
        Update()
    end)
end)
