local bossPulls = {}  -- tabla que almacena los registros de pulls de jefes

if bossHistoryList then wipe(bossHistoryList) end
if bossActivations then wipe(bossActivations) end
if listLines then
    for _, line in ipairs(listLines) do
        line:Hide()
    end
    wipe(listLines)
end

function ClearPulls()
    -- Borrar completamente el historial de activaciones (tanto datos lógicos como visuales)
    if BossPullTrackerDB and BossPullTrackerDB.bossHistoryList then
        wipe(BossPullTrackerDB.bossHistoryList)   -- Vaciar la lista de historial guardada (datos persistentes)
    end
    if BossPullTrackerDB and BossPullTrackerDB.bossActivations then
        wipe(BossPullTrackerDB.bossActivations)   -- Vaciar el registro de jefes activados actual
    end
    -- Limpiar la lista en la interfaz gráfica
    if type(ClearBossListUI) == "function" then
        ClearBossListUI()   -- Eliminar todas las líneas visuales de la lista (sin añadir entradas nuevas)
    end
end



-- Crear frame del panel de configuración
local panel = CreateFrame("Frame", "BossPullTrackerConfigPanel", UIParent)
panel.name = "BossPullTracker"  -- nombre que aparecerá en la lista de AddOns de Interfaz
InterfaceOptions_AddCategory(panel)

-- Checkbox "Mostrar/Ocultar addon"
local showCheckbox = CreateFrame("CheckButton", "BPT_ShowCheckbox", panel, "InterfaceOptionsCheckButtonTemplate")

-- Crear texto para el checkbox (WoW 3.3.5a no lo hace automáticamente)
local showCheckboxText = showCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
showCheckboxText:SetPoint("LEFT", showCheckbox, "RIGHT", 5, 0)
showCheckboxText:SetText("Activar seguimiento de jefes")

showCheckboxText:SetText("Activar seguimiento de jefes")
showCheckbox:SetChecked(true)  -- valor por defecto, asumimos que inicialmente se muestra
showCheckbox:SetScript("OnClick", function(self)
    if self:GetChecked() then
        BossPullTrackerFrame:Show()
    else
        BossPullTrackerFrame:Hide()
    end
    -- (Aquí podríamos guardar la preferencia en BossPullTrackerDB para persistencia)
end)

-- Botón "Borrar lista de activaciones"
local clearButton = CreateFrame("Button", "BPT_ClearButton", panel, "UIPanelButtonTemplate")
clearButton:SetSize(140, 22)
clearButton:SetPoint("TOPLEFT", showCheckbox, "BOTTOMLEFT", 0, -10)
clearButton:SetText("Borrar lista de pulls")
clearButton:SetScript("OnClick", function()
    ClearPulls()
end)
