local CreateProps = include("modules/fake_death_props.lua")

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
    [State.WRITHING] = { next = State.WRITHING, amount = 0 }
}

-- 根据状态设置正确的最大血量（用于 UI 显示）
local function setMaxHealthByState(ply, state)
    if state == State.COMBAT then
        ply:SetMaxHealth(DEFAULT_MAX_HEALTH)
    elseif state == State.STRUGGLING then
        ply:SetMaxHealth(STRUGGLING_HEALTH)
    else -- WRITHING
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
    while currentState ~= State.WRITHING and currentHealth + totalBonus - damage <= 0 do
        local transition = StateTransition[currentState]
        if not transition then break end
        totalBonus = totalBonus + transition.amount
        currentState = transition.next
    end

    -- 临时提高生命上限并补充血量（引擎随后会扣除 damage）
    ply:SetMaxHealth(ply:GetMaxHealth() + totalBonus)
    ply:SetHealth(currentHealth + totalBonus)
    ply.context.state = currentState
end

-- ScalePlayerDamage 钩子：仅在伤害致命时调用抢救逻辑
hook.Add("ScalePlayerDamage", "ScalePlayerDamage_EPDA_LifeCycle", function(ply, hitgroup, dmginfo)
    local damage = dmginfo:GetDamage()
    if damage > ply:Health() then
        if not ply.context then
            ply.context = { state = State.COMBAT }
        end

        handlePotentialDeath(ply, damage)

        if not ply.context.isPropCreated then
            ply.context.isPropCreated = true
            local props = CreateProps(ply)
            ply.context.ragdol = props.ragdol
            ply.context.animator = props.animator
            ply.context.follower = props.follower
        end
    end
end)

-- PlayerHurt 钩子：伤害结算后，根据最终状态刷新最大血量（UI 显示）
hook.Add("PlayerHurt", "PlayerHurt_EPDA_LifeCycle", function(ply, attacker, health, damage)
    -- 玩家死亡时不调整最大血量（保持原样或由重生逻辑重置）
    if ply:Health() <= 0 then return end

    -- 确保上下文存在（理论上 ScalePlayerDamage 已创建，但防御性处理）
    if not ply.context then
        ply.context = { state = State.COMBAT }
    end

    -- 根据当前状态设置正确的最大血量
    setMaxHealthByState(ply, ply.context.state)
end)

-- 重生时重置上下文和最大血量
hook.Add("PlayerSpawn", "PlayerSpawn_EPDA_LifeCycle", function(ply, transition)
    if transition then return end
    ply.context = nil
    -- ply:SetMaxHealth(DEFAULT_MAX_HEALTH)
    -- ply:SetHealth(DEFAULT_MAX_HEALTH)
end)
