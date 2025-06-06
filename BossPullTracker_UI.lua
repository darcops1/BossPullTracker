-- BossPullTracker_UI.lua: Creación y actualización de la ventana de interfaz del addon

-- Crear el marco principal de la UI para la lista de jefes
local UI = CreateFrame("Frame", "BossPullTrackerFrame", UIParent)

UI:SetSize(300, 200)
UI:SetPoint("CENTER")  -- Colocar al centro de la pantalla
UI:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
UI:SetBackdropColor(0, 0, 0, 0.8)

-- Habilitar arrastre del marco principal
UI:EnableMouse(true)
UI:SetMovable(true)
UI:RegisterForDrag("LeftButton")
UI:SetScript("OnDragStart", function(self) self:StartMoving() end)
UI:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

UI:EnableMouse(true)
UI:SetMovable(true)
UI:RegisterForDrag("LeftButton")
UI:SetScript("OnDragStart", function(self) self:StartMoving() end)
UI:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

UI:SetResizable(true)                        -- Permitir que el frame sea redimensionable
UI:SetMinResize(300, 150)                    -- Establecer un tamaño mínimo (evita que se haga demasiado pequeño)
UI:SetMaxResize(800, 600)                    -- (Opcional) Establecer un tamaño máximo para el frame
-- Agregar un "agarre" en la esquina inferior derecha para redimensionar manualmente
local resizeGrip = CreateFrame("Button", "BPT_ResizeGrip", UI)
resizeGrip:SetPoint("BOTTOMRIGHT", UI, "BOTTOMRIGHT", -6, 7)
resizeGrip:SetSize(16, 16)
resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
resizeGrip:SetScript("OnMouseDown", function(self)
    UI:StartSizing("BOTTOMRIGHT")            -- Comenzar a redimensionar desde la esquina inferior derecha
end)
resizeGrip:SetScript("OnMouseUp", function(self)
    UI:StopMovingOrSizing()                  -- Detener el movimiento/redimensionamiento al soltar
end)

-- Título del frame
local title = UI:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
title:SetPoint("TOP", 0, -10)
title:SetText("Activaciones de Jefes")  -- Texto de título de la ventana

-- Crear un ScrollFrame para contener la lista de activaciones de jefes
local scrollFrame = CreateFrame("ScrollFrame", "BossPullTrackerScrollFrame", UI, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", UI, "TOPLEFT", 10, -40)
scrollFrame:SetPoint("BOTTOMRIGHT", UI, "BOTTOMRIGHT", -30, 50)  -- Dejar espacio inferior para botones
-- Frame interno que contendrá las líneas de texto (FontStrings) con los datos
local content = CreateFrame("Frame", nil, scrollFrame)
content:SetSize(1, 1)  -- Tamaño inicial mínimo; se ajustará según contenido
scrollFrame:SetScrollChild(content)

-- Tabla para guardar los FontStrings de cada línea (para actualizarlos o limpiar fácilmente)
local listLines = {}

-- Función global: Añade un nuevo registro de jefe a la lista UI
function UpdateBossListUI(bossName, playerName, method)
    local boss = bossName or "Jefe desconocido"
    local player = playerName or "Jugador desconocido"
    local met = method or "desconocido"
    local text = string.format("%s – |cff00ff00%s|r (%s)", boss, player, met)

    local line = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if #listLines == 0 then
        line:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    else
        line:SetPoint("TOPLEFT", listLines[#listLines], "BOTTOMLEFT", 0, -2)
    end
    line:SetText(text)
    table.insert(listLines, line)

    local totalHeight = 0
    for _, fs in ipairs(listLines) do
        totalHeight = totalHeight + fs:GetHeight() + 2
    end
    content:SetHeight(totalHeight)
end


-- Función global: Limpia la lista de jefes en la UI (elimina todas las líneas)
function ClearBossListUI()
    -- Ocultar o reciclar todas las líneas existentes
    for _, fs in ipairs(listLines) do
        fs:SetText("")
        fs:Hide()
    end
    -- Reiniciar la tabla de líneas y la altura del frame de contenido
    listLines = {}
    content:SetHeight(1)
end

-- Botones para enviar la información al chat (Decir, Grupo, Banda, Hermandad)
local sayBtn = CreateFrame("Button", nil, UI, "UIPanelButtonTemplate")
sayBtn:SetSize(60, 20)
sayBtn:SetPoint("BOTTOMLEFT", UI, "BOTTOMLEFT", 10, 10)
sayBtn:SetText("Decir")
sayBtn:SetScript("OnClick", function()
    OutputActivationsToChat("SAY")
end)

local partyBtn = CreateFrame("Button", nil, UI, "UIPanelButtonTemplate")
partyBtn:SetSize(60, 20)
partyBtn:SetPoint("LEFT", sayBtn, "RIGHT", 5, 0)
partyBtn:SetText("Grupo")
partyBtn:SetScript("OnClick", function()
    OutputActivationsToChat("PARTY")
end)

local raidBtn = CreateFrame("Button", nil, UI, "UIPanelButtonTemplate")
raidBtn:SetSize(60, 20)
raidBtn:SetPoint("LEFT", partyBtn, "RIGHT", 5, 0)
raidBtn:SetText("Banda")
raidBtn:SetScript("OnClick", function()
    OutputActivationsToChat("RAID")
end)

local guildBtn = CreateFrame("Button", nil, UI, "UIPanelButtonTemplate")
guildBtn:SetSize(60, 20)
guildBtn:SetPoint("LEFT", raidBtn, "RIGHT", 5, 0)
guildBtn:SetText("Hermandad")
guildBtn:SetScript("OnClick", function()
    OutputActivationsToChat("GUILD")
end)
