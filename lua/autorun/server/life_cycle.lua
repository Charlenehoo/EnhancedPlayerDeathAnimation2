local CreateProps = include("modules/fake_death_props.lua")

util.AddNetworkString("EPDA_Ragdoll")

-- 常量定义
local DEFAULT_MAX_HEALTH = 100 -- 引擎默认生命上限（战斗状态）
local STRUGGLING_HEALTH = 100
local WRITHING_HEALTH = 50

-- 状态枚举（事实来源）
local State = {
    COMBAT = 1,     -- 剩余额外血量 = STRUGGLING_HEALTH + WRITHING_HEALTH
    STRUGGLING = 2, -- 剩余额外血量 = WRITHING_HEALTH
    WRITHING = 3    -- 剩余额外血量 = 0
}

-- 状态转移映射表：当前状态 -> { 下一状态, 本次兑现的份额 }
local StateTransition = {
    [State.COMBAT] = { next = State.STRUGGLING, amount = STRUGGLING_HEALTH },
    [State.STRUGGLING] = { next = State.WRITHING, amount = WRITHING_HEALTH },
    [State.WRITHING] = { next = nil, amount = 0 }
}

-- 根据状态设置正确的最大血量（用于 UI 显示）
local function setMaxHealthByState(ply, state)
    if state == State.STRUGGLING then
        ply:SetMaxHealth(STRUGGLING_HEALTH)
    elseif state == State.WRITHING then
        ply:SetMaxHealth(WRITHING_HEALTH)
    end
end

-- 核心函数：在 ScalePlayerDamage 阶段处理潜在致命伤害（仅在 damage > ply:Health() 时调用）
-- 副作用：临时提高生命上限、补充血量、更新 ply.context.state
local function handlePotentialDeath(ply, damage)
    local totalBonus = 0
    local currentHealth = ply:Health()
    local currentState = ply.context.state

    -- 递推兑现：使用映射表
    local transition = StateTransition[currentState]
    while transition and transition.next and currentHealth + totalBonus - damage <= 0 do
        totalBonus = totalBonus + transition.amount
        currentState = transition.next
        transition = StateTransition[currentState]
    end

    -- 临时提高生命上限并补充血量（引擎随后会扣除 damage）
    ply:SetMaxHealth(ply:GetMaxHealth() + totalBonus)
    ply:SetHealth(currentHealth + totalBonus)
    ply.context.state = currentState
end

local function handlePlayerTakeDamage(ply, dmginfo)
    local damage = dmginfo:GetDamage()
    if damage > ply:Health() then
        if not ply.context then
            ply.context = { state = State.COMBAT }
        end

        handlePotentialDeath(ply, damage)

        if not ply.context.hasTriggeredFakeDeath then
            ply.context.hasTriggeredFakeDeath = true
            local props = CreateProps(ply)
            ply.context.ragdoll = props.ragdoll
            ply.context.animator = props.animator
            ply.context.follower = props.follower

            net.Start("EPDA_Ragdoll")
            net.WriteEntity(ply.context.ragdoll)
            net.Send(ply)

            ply:SetModelScale(0.1, 0)
        end
    end
end

hook.Add("EntityTakeDamage", "EntityTakeDamage_EPDA_LifeCycle", function(target, dmginfo)
    if not IsValid(target) then return end
    if target:IsPlayer() then
        handlePlayerTakeDamage(target, dmginfo)
    elseif target:IsRagdoll() then

    end
end)

local function handlePostPlayerTakeDamage(ply, dmginfo, wasDamageTaken)
    if not ply.context then return end -- 未初始化，说明玩家处于 State.COMBAT，无需干预
    if not ply:Alive() then return end -- 玩家已死亡，无需干预

    setMaxHealthByState(ply, ply.context.state)
end

hook.Add("PostEntityTakeDamage", "PostEntityTakeDamage_EPDA_LifeCycle", function(ent, dmginfo, wasDamageTaken)
    if not IsValid(ent) then return end
    if ent:IsPlayer() then
        handlePostPlayerTakeDamage(ent, dmginfo, wasDamageTaken)
    elseif ent:IsRagdoll() then

    end
end)

hook.Add("PostPlayerDeath", "PostPlayerDeathe_EPDA_LifeCycle", function(ply)
    if not ply.context then return end

    local engineRagdoll = ply:GetRagdollEntity() -- assert(engineRagdoll == ply.context.ragdoll) -- false
    engineRagdoll:Remove()

    if IsValid(ply.context.animator) then
        ply.context.animator:Remove()
    end
    if IsValid(ply.context.follower) then
        ply.context.follower:Remove()
    end
end)

hook.Add("PlayerSpawn", "PlayerSpawn_EPDA_LifeCycle", function(ply, transition)
    net.Start("EPDA_Ragdoll")
    net.WriteEntity(nil)
    net.Send(ply)

    ply:SetModelScale(1, 0)

    if not ply.context then return end
    if IsValid(ply.context.ragdoll) then
        ply.context.ragdoll:Remove()
    end
    ply.context = nil
end)
