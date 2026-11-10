-- Guild Union - medidor de tirones dentro del juego (/gu perf) [+ARCHITECTURE.md]
local _, HU = ...
local L = HU.L

local Perf = {}
HU.Perf = Perf

Perf.FRAME_MS = 30     -- fotograma con tirón: el addon tardó esto o más en él
Perf.JUMP_KB = 1024    -- pico de memoria: la memoria de Lua creció esto o más de un fotograma al siguiente
Perf.KEEP = 10         -- peores fotogramas y picos que se guardan
Perf.MAX_LABELS = 400  -- causas distintas que se apuntan (el resto va a «(otros)»)
Perf.TOP = 15          -- causas que salen en el informe

local clock = debugprofilestop
local function Heap() return collectgarbage("count") end

local on = false
local origSafeCall, origAfter, origTicker
local depth = 0
local stats, nLabels = {}, 0
local slow, spikes = {}, {}
local slowCount, spikeCount, frames = 0, 0, 0
local over4 = 0 -- fotogramas en los que el addon tardó más de 4 ms (para el vigilante del modo sencillo)
local startT, startClock, lastHeap, peakHeap
-- lo de este fotograma
local fMs, fKB, fTop, fTopMs, fTopKB, fTopKBLabel = 0, 0, nil, 0, 0, nil

-- nombre de la función: archivo:línea (una vez por función; si el juego no tiene debug.getinfo, nada)
local names = setmetatable({}, { __mode = "k" })
local getinfo = type(debug) == "table" and type(debug.getinfo) == "function" and debug.getinfo or nil
local function FnName(fn)
    local n = names[fn]
    if n ~= nil then return n end
    n = false
    if getinfo then
        local ok, info = pcall(getinfo, fn, "S")
        if ok and type(info) == "table" and type(info.short_src) == "string" then
            n = (info.short_src:match("([^/\\]+)$") or info.short_src) .. ":" .. tostring(info.linedefined or "?")
        end
    end
    names[fn] = n
    return n
end

-- sin debug.getinfo: el origen del temporizador se toma al crearlo (solo con el medidor encendido)
local function Origin()
    if not debugstack then return nil end
    local s = debugstack(3, 1, 0) or ""
    local file, line = s:match("([^/\\]+%.lua)%]?:(%d+)")
    return file and (file .. ":" .. line) or nil
end

local function Label(where, fn, a, b)
    local label = tostring(where)
    if where == "CHAT_MSG_ADDON" then
        if type(a) == "string" and a:sub(1, 4) == "HU20" then
            -- (el tipo, con «~» detrás o solo, como HY, RQ, PA, CQ, PQ, NK; igual que lo lee Comm.lua)
            local kind = type(b) == "string" and (b:match("^(%u%u?)~") or b:match("^(%u%u?)$"))
            label = label .. " " .. a .. " " .. (kind or "?")
        else
            label = label .. " (otros addons)"
        end
    end
    local name = type(fn) == "function" and FnName(fn)
    if name then label = label .. " " .. name end
    return label
end

local function Keep(list, item, field)
    list[#list + 1] = item
    table.sort(list, function(x, y) return x[field] > y[field] end)
    while #list > Perf.KEEP do table.remove(list) end
end

local function Account(label, ms, kb)
    local s = stats[label]
    if not s then
        if nLabels >= Perf.MAX_LABELS then
            label = "(otros)"
            s = stats[label]
        end
        if not s then
            s = { n = 0, ms = 0, max = 0, kb = 0 }
            stats[label] = s
            nLabels = nLabels + 1
        end
    end
    s.n, s.ms, s.kb = s.n + 1, s.ms + ms, s.kb + kb
    if ms > s.max then s.max = ms end
    fMs, fKB = fMs + ms, fKB + kb
    if ms > fTopMs then fTop, fTopMs = label, ms end
    if kb > fTopKB then fTopKBLabel, fTopKB = label, kb end
end

-- HU:SafeCall medido: solo la llamada de fuera (las de dentro ya cuentan en ella)
local function TimedSafeCall(self, where, fn, ...)
    if depth > 0 then return origSafeCall(self, where, fn, ...) end
    depth = 1
    local k0, t0 = Heap(), clock()
    local ok = origSafeCall(self, where, fn, ...)
    local ms, kb = clock() - t0, Heap() - k0
    depth = 0
    if kb < 0 then kb = 0 end -- (el recolector de basura pasó por medio)
    local a, b = ...
    Account(Label(where, fn, a, b), ms, kb)
    return ok
end

local function WrapTimer(fn, origin)
    if not origin or getinfo then return fn end
    if names[fn] == nil then names[fn] = origin end
    return fn
end
local function TimedAfter(delay, fn) return origAfter(delay, WrapTimer(fn, Origin())) end
local function TimedTicker(delay, fn, n) return origTicker(delay, WrapTimer(fn, Origin()), n) end

local updater = CreateFrame("Frame")
updater:Hide()
updater:SetScript("OnUpdate", function()
    frames = frames + 1
    local now = time()
    if fMs > 4 then over4 = over4 + 1 end
    if fMs >= Perf.FRAME_MS then
        slowCount = slowCount + 1
        Keep(slow, { t = now, ms = fMs, label = fTop or "?", lms = fTopMs }, "ms")
    end
    local h = Heap()
    if lastHeap and h - lastHeap >= Perf.JUMP_KB then
        spikeCount = spikeCount + 1
        Keep(spikes, { t = now, kb = h - lastHeap, ours = fKB, label = fTopKBLabel or "-", lkb = fTopKB }, "kb")
    end
    lastHeap = h
    if not peakHeap or h > peakHeap then peakHeap = h end
    fMs, fKB, fTop, fTopMs, fTopKB, fTopKBLabel = 0, 0, nil, 0, 0, nil
end)

function Perf.Reset()
    wipe(stats); wipe(slow); wipe(spikes)
    nLabels, slowCount, spikeCount, frames, over4 = 0, 0, 0, 0, 0
    startT, startClock, lastHeap, peakHeap = time(), clock(), nil, nil
    fMs, fKB, fTop, fTopMs, fTopKB, fTopKBLabel = 0, 0, nil, 0, 0, nil
end

function Perf.Start()
    if on then return end
    on = true
    origSafeCall, origAfter, origTicker = HU.SafeCall, HU.After, HU.NewTicker
    HU.SafeCall, HU.After, HU.NewTicker = TimedSafeCall, TimedAfter, TimedTicker
    Perf.Reset()
    updater:Show()
    if HU.db then HU.db.perfOn = true end
end

function Perf.Stop()
    if not on then return end
    Perf.SaveSummary()
    on = false
    updater:Hide()
    -- (solo se devuelve lo nuestro si nadie lo ha cambiado después)
    if HU.SafeCall == TimedSafeCall then HU.SafeCall = origSafeCall end
    if HU.After == TimedAfter then HU.After = origAfter end
    if HU.NewTicker == TimedTicker then HU.NewTicker = origTicker end
    if HU.db then HU.db.perfOn = nil end
end

function Perf.IsOn() return on end
-- (nil si el medidor está apagado)
function Perf.Over4() return on and over4 or nil end

local function Minutes() return startClock and (clock() - startClock) / 60000 or 0 end

-- lo único que se guarda: un resumen corto de la última sesión medida
function Perf.SaveSummary()
    if not on or not HU.db then return end
    local top, topMs
    for label, s in pairs(stats) do
        if not topMs or s.ms > topMs then top, topMs = label, s.ms end
    end
    HU.db.perfLast = {
        t = time(), v = HU.version, min = math.floor(Minutes() + 0.5), frames = frames,
        slow = slowCount, worst = slow[1] and math.floor(slow[1].ms + 0.5) or 0, worstWhat = slow[1] and slow[1].label or nil,
        spikes = spikeCount, spikeKB = spikes[1] and math.floor(spikes[1].kb) or 0,
        top = top, topMs = topMs and math.floor(topMs + 0.5) or 0,
    }
end

local function Clock(t) return date("%H:%M:%S", t) end
local function Ms(x) return string.format("%.1f", x) end

function Perf.Report()
    local lines = {}
    local function Add(s) lines[#lines + 1] = s end
    Add(HU.ADDON_TITLE .. " " .. tostring(HU.version) .. " - " .. L("medidor de tirones") .. " - " .. date("%d/%m/%Y %H:%M"))
    if not on then
        Add(L("El medidor está apagado. Enciéndelo con /gu perf on y juega un rato."))
        local p = HU.db and HU.db.perfLast
        if p then
            Add("")
            Add(L("Última sesión medida") .. " (" .. date("%d/%m %H:%M", p.t) .. ", " .. tostring(p.min) .. " min): "
                .. string.format(L("%d tirones (peor %d ms), %d picos de memoria (mayor %d KB)"), p.slow or 0, p.worst or 0, p.spikes or 0, p.spikeKB or 0))
            if p.worstWhat then Add(L("Peor tirón: ") .. p.worstWhat) end
            if p.top then Add(L("Lo que más tiempo se llevó: ") .. p.top .. " (" .. tostring(p.topMs) .. " ms)") end
        end
        return table.concat(lines, "\n")
    end
    Add(string.format(L("Encendido desde las %s (%d min). Fotogramas medidos: %d."), Clock(startT), math.floor(Minutes() + 0.5), frames))
    Add("")
    if slowCount == 0 and spikeCount == 0 then
        Add(L("VEREDICTO: el addon no ha dado ningún tirón."))
    else
        Add(string.format(L("VEREDICTO: %d tirones del addon (fotogramas de %d ms o más) y %d picos de memoria (%d KB o más)."),
            slowCount, Perf.FRAME_MS, spikeCount, Perf.JUMP_KB))
    end
    Add(string.format(L("Memoria de Lua más alta vista: %.1f MB (de todos los addons juntos)."), (peakHeap or Heap()) / 1024))
    if #slow > 0 then
        Add("")
        Add(L("-- Peores fotogramas (hora, ms del addon, qué se llevó más) --"))
        for _, e in ipairs(slow) do Add(Clock(e.t) .. "  " .. Ms(e.ms) .. " ms  " .. e.label .. " (" .. Ms(e.lms) .. " ms)") end
    end
    if #spikes > 0 then
        Add("")
        Add(L("-- Picos de memoria (hora, subida total, lo que hizo el addon) --"))
        for _, e in ipairs(spikes) do
            Add(Clock(e.t) .. "  +" .. math.floor(e.kb) .. " KB  " .. L("del addon: ") .. math.floor(e.ours) .. " KB  " .. e.label .. " (" .. math.floor(e.lkb) .. " KB)")
        end
        Add(L("(Si «del addon» es pequeño, la subida la causó otro addon o el juego.)"))
    end
    local list = {}
    for label, s in pairs(stats) do list[#list + 1] = { label = label, s = s } end
    table.sort(list, function(x, y) return x.s.ms > y.s.ms end)
    if #list > 0 then
        Add("")
        Add(L("-- Lo que más tiempo se lleva (veces, ms en total, ms la peor, KB) --"))
        for i = 1, math.min(Perf.TOP, #list) do
            local e = list[i]
            Add(e.s.n .. "x  " .. Ms(e.s.ms) .. "  " .. Ms(e.s.max) .. "  " .. math.floor(e.s.kb) .. "  " .. e.label)
        end
    end
    Add("")
    Add(L("(Mide eventos, temporizadores e inicio del addon; no el dibujo de las ventanas.)"))
    return table.concat(lines, "\n")
end

local function Short()
    if slowCount == 0 and spikeCount == 0 then return L("sin tirones del addon") .. " (" .. math.floor(Minutes() + 0.5) .. " min)" end
    return string.format(L("%d tirones (peor %d ms), %d picos de memoria"), slowCount, slow[1] and math.floor(slow[1].ms + 0.5) or 0, spikeCount)
end

-- /gu perf [on | off | reset]
function HU:PerfCommand(arg)
    arg = arg or ""
    if arg == "on" or arg == "encender" then
        Perf.Start()
        self:Print(L("Medidor de tirones encendido. Juega normal y escribe /gu perf para ver el resultado (/gu perf off para apagarlo)."))
    elseif arg == "off" or arg == "apagar" then
        if on then self:Print(L("Medidor apagado: ") .. Short()) else self:Print(L("El medidor está apagado.")) end
        Perf.Stop()
    elseif arg == "reset" or arg == "borrar" then
        if on then Perf.Reset() end
        self:Print(L("Medidor puesto a cero."))
    else
        if on then
            Perf.SaveSummary()
            self:Print(L("Medidor: ") .. Short())
        end
        if HU.UI and HU.UI.ShowCopy then HU.UI:ShowCopy(L("Medidor de tirones (Ctrl+C y mándaselo a quien lleva el addon)"), Perf.Report())
        else for l in Perf.Report():gmatch("[^\n]+") do self:Print(l) end end
    end
end

-- si estaba encendido antes de /reload, sigue encendido; al salir se guarda el resumen
HU:OnStart(function() if HU.db and HU.db.perfOn then Perf.Start() end end)
HU:On("PLAYER_LOGOUT", function() Perf.SaveSummary() end)

-- textos en inglés
local E = HU.EN
if E then
    E["medidor de tirones"] = "stutter meter"
    E["El medidor está apagado. Enciéndelo con /gu perf on y juega un rato."] = "The meter is off. Turn it on with /gu perf on and play for a while."
    E["Última sesión medida"] = "Last measured session"
    E["%d tirones (peor %d ms), %d picos de memoria (mayor %d KB)"] = "%d stutters (worst %d ms), %d memory spikes (largest %d KB)"
    E["Peor tirón: "] = "Worst stutter: "
    E["Lo que más tiempo se llevó: "] = "Most time spent in: "
    E["Encendido desde las %s (%d min). Fotogramas medidos: %d."] = "On since %s (%d min). Frames measured: %d."
    E["VEREDICTO: el addon no ha dado ningún tirón."] = "VERDICT: the addon caused no stutter."
    E["VEREDICTO: %d tirones del addon (fotogramas de %d ms o más) y %d picos de memoria (%d KB o más)."] = "VERDICT: %d addon stutters (frames of %d ms or more) and %d memory spikes (%d KB or more)."
    E["Memoria de Lua más alta vista: %.1f MB (de todos los addons juntos)."] = "Highest Lua memory seen: %.1f MB (all addons together)."
    E["-- Peores fotogramas (hora, ms del addon, qué se llevó más) --"] = "-- Worst frames (time, addon ms, biggest cause) --"
    E["-- Picos de memoria (hora, subida total, lo que hizo el addon) --"] = "-- Memory spikes (time, total rise, addon's part) --"
    E["del addon: "] = "addon: "
    E["(Si «del addon» es pequeño, la subida la causó otro addon o el juego.)"] = "(If the addon's part is small, another addon or the game caused it.)"
    E["-- Lo que más tiempo se lleva (veces, ms en total, ms la peor, KB) --"] = "-- Most time spent (calls, total ms, worst ms, KB) --"
    E["(Mide eventos, temporizadores e inicio del addon; no el dibujo de las ventanas.)"] = "(Measures the addon's events, timers and startup; not window drawing.)"
    E["sin tirones del addon"] = "no addon stutters"
    E["%d tirones (peor %d ms), %d picos de memoria"] = "%d stutters (worst %d ms), %d memory spikes"
    E["Medidor de tirones encendido. Juega normal y escribe /gu perf para ver el resultado (/gu perf off para apagarlo)."] = "Stutter meter on. Play normally and type /gu perf to see the result (/gu perf off to turn it off)."
    E["Medidor apagado: "] = "Meter off: "
    E["El medidor está apagado."] = "The meter is off."
    E["Medidor puesto a cero."] = "Meter reset."
    E["Medidor: "] = "Meter: "
    E["Medidor de tirones (Ctrl+C y mándaselo a quien lleva el addon)"] = "Stutter meter (Ctrl+C and send it to the addon's maintainer)"
end
