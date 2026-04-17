-- 辅助函数：格式化打印
local function LogHook(hookName, ply, extra)
    local health = IsValid(ply) and ply:Health() or "N/A"
    local name = IsValid(ply) and ply:Nick() or "Unknown"
    local time = SysTime()
    print(string.format("[%.4f] %s | %s | HP: %s | %s",
        time, hookName, name, tostring(health), extra or ""))
end

-- 1. 伤害修正钩子（伤害尚未扣除）
hook.Add("ScalePlayerDamage", "EPDA_Test_ScaleDamage", function(ply, hitgroup, dmginfo)
    local dmg = dmginfo:GetDamage()
    LogHook("ScalePlayerDamage", ply, string.format("IncomingDmg: %.1f", dmg))
end)

-- 2. 实体承受伤害前的通用钩子（可用于阻止伤害）
hook.Add("EntityTakeDamage", "EPDA_Test_EntityTakeDamage", function(ent, dmginfo)
    if not ent:IsPlayer() then return end
    local dmg = dmginfo:GetDamage()
    local healthBefore = ent:Health()
    LogHook("EntityTakeDamage", ent, string.format("Dmg: %.1f | HPBefore: %d", dmg, healthBefore))
end)

-- 3. 玩家受伤钩子（伤害已扣除，参数为剩余血量和伤害量）
hook.Add("PlayerHurt", "EPDA_Test_PlayerHurt", function(victim, attacker, healthRemaining, damageTaken)
    LogHook("PlayerHurt", victim, string.format("Remaining: %d | Taken: %.1f", healthRemaining, damageTaken))
end)

-- 4. 伤害结算后钩子（伤害已完全处理，包括护甲等）
hook.Add("PostEntityTakeDamage", "EPDA_Test_PostEntityDamage", function(ent, dmginfo, tookDamage)
    if not ent:IsPlayer() then return end
    local dmg = dmginfo:GetDamage()
    LogHook("PostEntityTakeDamage", ent, string.format("TookDamage: %s | Dmg: %.1f", tostring(tookDamage), dmg))
end)

-- 5. 玩家死亡钩子（最终结果）
hook.Add("PlayerDeath", "EPDA_Test_PlayerDeath", function(victim, inflictor, attacker)
    LogHook("PlayerDeath", victim, "Died")
end)

-- 可选：在玩家重生时也打印一下，便于观察周期
hook.Add("PlayerSpawn", "EPDA_Test_PlayerSpawn", function(ply)
    LogHook("PlayerSpawn", ply, "Spawned")
end)

print("[EPDA Hook Tester] 所有伤害相关钩子已挂载，输出 SysTime + 玩家 + 血量信息。")
