-- Guild Union - pedir los errores guardados de todos (con contraseña)
local _, HU = ...
local L = HU.L

-- (descripción del protocolo y detalles: ARCHITECTURE.md)

local ASK_WINDOW = 600   -- durante 10 min se aceptan respuestas a mi petición
local MAX_SEND = 10

local function Clean(s) return (tostring(s or ""):gsub("[~|\r\n]", " ")) end

local function Sign(pass, who, id)
    return HU.Hash(tostring(pass) .. ":" .. tostring(HU:Key(who) or who):lower() .. ":" .. tostring(id))
end

local function Password()
    return HU.cfg and HU.cfg.password
end

local function Broadcast(self, raw)
    self:Send(raw, "GUILD")
    for _, ot in ipairs(self:OtherTags()) do
        local peer = self:BestPeer(ot)
        if peer then self:Whisper(peer.name, raw) end
    end
end

local seen, answered = {}, {}
local myAsk -- { id, t }

-- Pedir los errores a todos (devuelve false y el motivo si no se puede)
function HU:AskErrors(pass)
    local real = Password()
    if not real or real == "" then return false, L("no hay contraseña del chat configurada") end
    if not pass or pass ~= real then return false, L("contraseña incorrecta") end
    local id = tostring(time() % 1000000) .. tostring(math.random(10, 99))
    myAsk = { id = id, t = time() }
    seen[id] = true
    Broadcast(self, table.concat({ "EQ", id, self:Me(), Sign(real, self:Me(), id) }, "~"))
    return true
end

-- Mis errores guardados, para mandar
local function MyErrors(self)
    local out = {}
    for _, e in ipairs(self.db and self.db.lastErrors or {}) do
        if #out >= MAX_SEND then break end
        local first = (e.stack or ""):match("[^\n]+") or ""
        local msg = e.msg or "?"
        if first ~= "" and not msg:find(first, 1, true) then msg = msg .. " @ " .. first end
        out[#out + 1] = { v = e.v or self.version, where = e.where or "?", msg = msg, t = e.t }
    end
    return out
end

HU.comm.EQ = function(self, sender, f, dist, raw)
    local id, by, sig = f[1], f[2], f[3]
    if not id or not by or by == "" or not sig or seen[id] then return end
    if not self:IsTest() and (self:TrustedOfficer(by) ~= true or not self:MayCarry(by, sender, dist)) then return end
    if not HU.RequestRate("EQ:" .. by) then return end
    seen[id] = true
    local real = Password()
    if not real or Sign(real, by, id) ~= sig then return end
    -- pasarla a las demás hermandades
    if dist == "WHISPER" then
        self:Send(raw, "GUILD")
    elseif self:IsRelay() then
        for _, ot in ipairs(self:OtherTags()) do
            local peer = self:BestPeer(ot)
            if peer then self:Whisper(peer.name, raw) end
        end
    end
    if answered[id] or (self:Key(by) == self:MeKey()) then return end
    answered[id] = true
    local list = MyErrors(self)
    if #list == 0 then return end
    -- cada uno contesta en un momento distinto (para no juntarse todos)
    HU.After(1 + math.random() * 25, function()
        for _, e in ipairs(list) do
            self:Whisper(by, HU.Utf8Cut(table.concat({ "ER", id, self:Me(), Clean(e.v), Clean(e.where), Clean(e.msg) }, "~"), 250))
        end
    end)
end

HU.comm.ER = function(self, sender, f)
    local id, from, v, where, msg = f[1], f[2], f[3], f[4], f[5]
    if not myAsk or id ~= myAsk.id or time() - myAsk.t > ASK_WINDOW or not msg then return end
    from = (from and from ~= "") and from or sender
    self.db.errIn = self.db.errIn or {}
    local box = self.db.errIn
    for _, e in ipairs(box) do
        if e.from == from and e.msg == msg then e.t = time() return end
    end
    table.insert(box, 1, { from = from, v = v, where = where, msg = msg, t = time() })
    while #box > 200 do table.remove(box) end
    myAsk.n = (myAsk.n or 0) + 1
    if myAsk.n == 1 then
        self:Print(L("Están llegando errores de otros jugadores. /gu errores para verlos."))
    end
end

-- Texto de los errores recibidos (para /gu errores)
function HU:ReceivedErrorsText()
    local box = self.db and self.db.errIn or {}
    if #box == 0 then return nil end
    local lines = { "", L("— Errores recibidos de otros jugadores —") }
    for _, e in ipairs(box) do
        lines[#lines + 1] = HU.SafeDate("%d/%m %H:%M", e.t) .. "  " .. self:Short(e.from or "?") .. "  v" .. tostring(e.v)
            .. "  [" .. tostring(e.where) .. "]  " .. tostring(e.msg)
    end
    return table.concat(lines, "\n")
end

function HU:ClearReceivedErrors()
    local n = self.db and self.db.errIn and #self.db.errIn or 0
    if self.db then self.db.errIn = nil end
    return n
end
