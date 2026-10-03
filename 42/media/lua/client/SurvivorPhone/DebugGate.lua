SurvivorPhoneDebug = SurvivorPhoneDebug or {}

-- Keep debug utilities owned by the mod.  This conservative gate avoids changing
-- or monkey-patching The Indie Stone's DebugUIs files.
function SurvivorPhoneDebug.isEnabled()
    if getCore and getCore().getDebug then return getCore():getDebug() == true end
    if isDebugEnabled then return isDebugEnabled() == true end
    if getDebug then return getDebug() == true end
    return false
end

return SurvivorPhoneDebug
