local CreateProps = include("modules/fake_death_props.lua")

util.AddNetworkString("EPDA_Ragdoll")

local BONE_NAME_HEAD = "ValveBiped.Bip01_Head1"

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
-- 副作用：临时提高生命上限、补充血量、更新 ply.EPDAContext.state
local function handlePotentialDeath(ply, damage)
    local totalBonus = 0
    local currentHealth = ply:Health()
    local currentState = ply.EPDAContext.state

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
    ply.EPDAContext.state = currentState
end

local function handlePlayerTakeDamage(ply, dmginfo)
    local damage = dmginfo:GetDamage()
    if damage > ply:Health() then
        if not ply.EPDAContext then
            ply.EPDAContext = { state = State.COMBAT }
        end

        handlePotentialDeath(ply, damage)

        if not ply.EPDAContext.hasTriggeredFakeDeath then
            ply.EPDAContext.hasTriggeredFakeDeath = true
            local props = CreateProps(ply)
            ply.EPDAContext.ragdoll = props.ragdoll
            ply.EPDAContext.animator = props.animator
            ply.EPDAContext.follower = props.follower

            net.Start("EPDA_Ragdoll")
            net.WriteEntity(ply.EPDAContext.ragdoll)
            net.Send(ply)

            ply:SetModelScale(0, 0)
            -- ply:Freeze(true)
            ply:SetMoveType(MOVETYPE_NONE)
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
    if not ply.EPDAContext then return end -- 未初始化，说明玩家处于 State.COMBAT，无需干预
    if not ply:Alive() then return end     -- 玩家已死亡，无需干预

    ply:SetPos(ply.EPDAContext.ragdoll:GetPos())

    setMaxHealthByState(ply, ply.EPDAContext.state)
end

local function handlePostRagdollTakeDamage(ragdoll, dmginfo, wasDamageTaken)
    local ply = ragdoll.EPDAOwner
    if IsValid(ply) then
        ply:TakeDamageInfo(dmginfo)
    end
end

hook.Add("PostEntityTakeDamage", "PostEntityTakeDamage_EPDA_LifeCycle", function(ent, dmginfo, wasDamageTaken)
    if not IsValid(ent) then return end
    if not wasDamageTaken then return end
    if ent:IsPlayer() then
        handlePostPlayerTakeDamage(ent, dmginfo, wasDamageTaken)
    elseif ent:IsRagdoll() and ent.EPDACustomEntFlag then
        handlePostRagdollTakeDamage(ent, dmginfo, wasDamageTaken)
    end
end)

hook.Add("PostPlayerDeath", "PostPlayerDeathe_EPDA_LifeCycle", function(ply)
    ply:SetModelScale(1, 0)
    ply:Freeze(false)
    ply:SetMoveType(MOVETYPE_WALK)
    if not ply.EPDAContext then return end

    local engineRagdoll = ply:GetRagdollEntity() -- assert(engineRagdoll == ply.EPDAContext.ragdoll) -- false
    engineRagdoll:Remove()

    if IsValid(ply.EPDAContext.animator) then
        ply.EPDAContext.animator:Remove()
    end
    if IsValid(ply.EPDAContext.follower) then
        ply.EPDAContext.follower:Remove()
    end
end)

hook.Add("PlayerSpawn", "PlayerSpawn_EPDA_LifeCycle", function(ply, transition)
    net.Start("EPDA_Ragdoll")
    net.WriteEntity(nil)
    net.Send(ply)

    if not ply.EPDAContext then return end
    if IsValid(ply.EPDAContext.ragdoll) then
        ply.EPDAContext.ragdoll:Remove()
    end
    ply.EPDAContext = nil
end)

hook.Add("PlayerTick", "PlayerTick_EPDA_LifeCycle", function(ply, mv)
    if not ply.EPDAContext or not IsValid(ply.EPDAContext.ragdoll) then return end
    local boneIDHead = ply.EPDAContext.ragdoll:LookupBone(BONE_NAME_HEAD)
    if not boneIDHead then return end
    local posHead, _ = ply.EPDAContext.ragdoll:GetBonePosition(boneIDHead)
    ply:SetPos(posHead)
end)
