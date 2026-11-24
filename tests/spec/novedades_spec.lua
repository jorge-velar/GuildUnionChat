-- Lo que trajeron la 5.4.42 y la 5.4.43 (copias 161 a 175), que llegaron a main sin pruebas: el canal
-- fantasma, la vuelta del servidor de chat, el aviso de fuera del canal (a /gu informe), lo que se
-- perdió durante un bloqueo del chat y el color de clase con Prat
local F = require("lib.fixtures")
local addon = require("lib.addon")
local A = assert_

-- Lo que el addon ha escrito en el chat desde i0
local function ChatSince(a, i0)
    local out = {}
    for i = i0 or 1, #a.w.chat do out[#out + 1] = tostring(a.w.chat[i].msg) end
    return table.concat(out, "\n")
end

describe("Canal fantasma (Channel.lua)", function()
    local a, HU, c
    before_each(function()
        a = F.Community()
        HU = a.HU
        c = HU.chan.main
        assert(c and c.name and HU:IsJoined("main"), "la comunidad de prueba no ha entrado al canal")
    end)

    it("¿sale en la lista de canales? sí, no, o no se sabe si hay un grupo plegado", function()
        A.equal(true, HU.ChannelListed(HU:ChannelId("main")))
        A.equal(false, HU.ChannelListed(999))
        a.env.GetNumDisplayChannels = function() return 1 end
        a.env.GetChannelDisplayInfo = function() return "Grupo", true, true end
        A.equal(nil, HU.ChannelListed(999))
    end)

    it("si no sale en la lista tres veces seguidas, sale y vuelve a entrar (como mucho una vez por minuto)", function()
        a.env.GetNumDisplayChannels = function() return 0 end
        HU:CheckGhostChannels(); HU:CheckGhostChannels()
        A.equal(0, c.rejoinN or 0, "con dos no")
        HU:CheckGhostChannels()
        A.equal(1, c.rejoinN)
        A.falsy(HU:IsJoined("main"), "ha salido")
        a.w:Advance(3)
        A.truthy(a.w.channels[HU:ChannelId("main")], "ha vuelto a entrar")
        HU:RejoinChannel("main", "otra vez")
        A.equal(1, c.rejoinN, "antes del minuto, no")
        -- (vuelve a salir en la lista: se olvidan los intentos)
        a.env.GetNumDisplayChannels = nil
        a.w:Advance(1)
        HU:CheckGhostChannels()
        A.equal(0, c.rejoinN)
        A.same({}, a:Errors())
    end)

    it("tras cinco intentos se rinde, sin avisar en el chat", function()
        c.rejoinN = 5
        local i0 = #a.w.chat + 1
        HU:RejoinChannel("main", "prueba")
        A.truthy(c.rejoinWarned)
        A.equal(5, c.rejoinN)
        A.equal("", ChatSince(a, i0))
    end)

    it("cuando vuelve el servidor de chat, basta con dos veces seguidas", function()
        a.w:Fire("CHAT_SERVER_DISCONNECTED")
        A.truthy(HU.chatServerDownT)
        a.w:Fire("CHAT_SERVER_RECONNECTED")
        A.truthy(HU.chatServerUpT)
        a.env.GetNumDisplayChannels = function() return 0 end
        -- (las comprobaciones de los 5 y los 15 s: dos seguidas sin el canal)
        a.w:Advance(16)
        A.equal(1, c.rejoinN)
        A.same({}, a:Errors())
    end)
end)

describe("Aviso de fuera del canal (Channel.lua): a /gu informe, no al chat", function()
    it("sin el canal: se guarda el aviso de que falta, una vez", function()
        local a = F.Community()
        local HU = a.HU
        HU.chan.main.name = nil
        a.env.LeaveChannelByName("CanalPrueba")
        local i0 = #a.w.chat + 1
        a.w:Advance(400)
        local found = 0
        for _, n in ipairs(HU.notices) do if n.text:find("Te falta el canal", 1, true) then found = found + 1 end end
        A.equal(1, found, "el aviso, una vez")
        A.falsy(ChatSince(a, i0):find("Te falta el canal", 1, true), "y no en el chat")
    end)

    it("el informe dice qué le pasa al canal: los avisos del servidor y cuándo intento entrar o salgo yo (Jorge, 25/11)", function()
        local a = F.Community()
        local HU = a.HU
        a.env.LeaveChannelByName("CanalPrueba")
        a.w:Advance(30)
        local whats = {}
        for _, e in ipairs(HU.chanEvents) do whats[#whats + 1] = e.what end
        local all = table.concat(whats, " | ")
        A.truthy(all:find("YOU_LEFT", 1, true), all)
        A.truthy(all:find("intento entrar", 1, true), all)
        A.truthy(all:find("YOU_JOINED", 1, true), all)
        -- (y sale en el informe completo, detrás de «fuera del canal»)
        local got
        if HU.UI then HU.UI.ShowCopy = function(_, _, text) got = text end end
        local i0 = #a.w.chat + 1
        HU:FullReport()
        a.w:Advance(5)
        got = got or ChatSince(a, i0)
        A.truthy(got:find("  canal: ", 1, true) and got:find("YOU_JOINED", 1, true), "en el informe")
    end)
end)

describe("Lo que se perdió durante un bloqueo del chat (Combat.lua y Social.lua)", function()
    it("al acabar el bloqueo se pide lo que se perdió", function()
        local a = F.Community()
        local HU = a.HU
        local asked
        HU.AskMissedChat = function(_, since) asked = since end
        local locked = true
        HU.IsChatLockedDown = function() return locked end
        a.w:Advance(4)
        locked = false
        a.w:Advance(6)
        A.truthy(asked, "lo ha pedido")
        A.truthy(HU.showLateUntil, "lo que llegue se escribe en el chat")
    end)

    local function Late(HU, n)
        local h = HU.db.history
        for i = 1, n do h[#h + 1] = { k = "main", tag = "DOS", a = "Bea-Reino", m = "línea " .. i, t = 0, late = true } end
        h[#h + 1] = { k = "main", tag = "UNO", a = "Compi-Reino", m = "de mi hermandad", t = 0, late = true }
    end

    it("tras el bloqueo se escribe en el chat, sin lo de mi hermandad, y en banda con tope", function()
        local a = F.Community()
        local HU = a.HU
        local lines = {}
        local frame = { AddMessage = function(_, msg) lines[#lines + 1] = msg end }
        HU.FramesFor = function() return { frame } end
        Late(HU, 3)
        HU.showLateUntil = a.w.now + 60
        HU.showLateLeft = 2
        HU:ShowLate(4)
        local text = table.concat(lines, "\n")
        A.matches("Mientras el chat estaba bloqueado %(3%)", text)
        A.matches("%(%+1 más en el panel de", text)
        A.falsy(text:find("de mi hermandad", 1, true), "lo de mi hermandad ya lo pintó el juego")
        A.truthy(text:find("línea 3", 1, true) and not text:find("línea 1", 1, true), "las últimas")
        A.equal(0, HU.showLateLeft)
        -- (sin sitio: solo el aviso)
        local i0 = #a.w.chat + 1
        lines = {}
        Late(HU, 2)
        HU:ShowLate(2)
        A.equal(0, #lines)
        A.matches("Mientras el chat estaba bloqueado: 2 más en el panel", ChatSince(a, i0))
    end)
end)

describe("Prat: el nombre con el color de su clase (PratBridge.lua)", function()
    local function WithPrat(colormode)
        local a = addon.Load({ guild = F.Guild(), guildInfo = F.INFO })
        local P = { colormode = colormode }
        P.prat = {
            Format = function()
                -- (Prat llama a su gancho con la línea por partes antes de juntarla)
                local m = { MESSAGE = "hola", PLAYER = "|cff808080Bea Reino|r", SERVER = "" }
                P.pre(nil, m, nil, "CHAT_MSG_GUILD")
                P.remote = m
                return "línea de Prat"
            end,
            RegisterChatEvent = function(_, _, fn) P.pre = fn end,
            GetModule = function()
                return { db = { profile = { colormode = P.colormode } }, addName = function() end }
            end,
        }
        a.env.Prat = P.prat
        a:Login(60)
        a.HU:RefreshConfig(true)
        return a, P
    end
    local function OwnLine(P)
        local m = { MESSAGE = "hola", PLAYER = "|cff808080Compi|r", SERVER = "", ARGS = { "hola", "Compi-Reino" } }
        P.pre(nil, m, nil, "CHAT_MSG_GUILD")
        return m
    end

    it("con «color por clase» en Prat, se le pone el color que sabe GuildUnion", function()
        local a, P = WithPrat("CLASS")
        local HU = a.HU
        HU.ClassFor = function() return "WARRIOR" end
        local m = OwnLine(P)
        local r, g, b = HU.ClassRGB("WARRIOR")
        A.equal(string.format("|cff%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)) .. "Compi|r", m.PLAYER)
        A.equal(1, HU.pratStats.class)
        -- (y en las líneas de otra hermandad, que se le piden a Prat)
        A.equal("línea de Prat", HU:PratLine(DEFAULT_CHAT_FRAME, "main", "DOS", "Bea-Reino", "hola", "guid"))
        A.equal(2, HU.pratStats.class)
        A.same({}, a:Errors())
    end)

    it("con otro modo de color, o sin clase sabida, se deja como lo pinta Prat", function()
        local a, P = WithPrat("NONE")
        a.HU.ClassFor = function() return "WARRIOR" end
        A.equal("|cff808080Compi|r", OwnLine(P).PLAYER)
        local b, Q = WithPrat("CLASS")
        b.HU.ClassFor = function() return nil end
        A.equal("|cff808080Compi|r", OwnLine(Q).PLAYER)
        A.equal(0, b.HU.pratStats.class or 0)
    end)
end)
