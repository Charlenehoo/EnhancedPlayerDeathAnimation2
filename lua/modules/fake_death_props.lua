local BONE_PELVIS   = "ValveBiped.Bip01_Pelvis"
local BONE_HEAD     = "ValveBiped.Bip01_Head1"
local BONE_L_FOOT   = "ValveBiped.Bip01_L_Foot"
local BONE_R_FOOT   = "ValveBiped.Bip01_R_Foot"

local AlignStrategy = {
    PELVIS_TO_HEAD = 1,
    FEET_TO_PELVIS = 2,
    FEET_TO_HEAD   = 3
}

local function getBoneData(ent, strategy)
    if strategy == AlignStrategy.PELVIS_TO_HEAD then
        local idxPelvis = ent:LookupBone(BONE_PELVIS)
        local idxHead   = ent:LookupBone(BONE_HEAD)
        if not idxPelvis or not idxHead then
            return nil, nil
        end
        local lowPos, _ = ent:GetBonePosition(idxPelvis)
        local highMat   = ent:GetBoneMatrix(idxHead)
        return lowPos, highMat
    elseif strategy == AlignStrategy.FEET_TO_PELVIS then
        local idxL = ent:LookupBone(BONE_L_FOOT)
        local idxR = ent:LookupBone(BONE_R_FOOT)
        local idxPelvis = ent:LookupBone(BONE_PELVIS)
        if not idxL or not idxR or not idxPelvis then
            return nil, nil
        end
        local posL, _ = ent:GetBonePosition(idxL)
        local posR, _ = ent:GetBonePosition(idxR)
        local lowPos = (posL + posR) * 0.5
        local highMat = ent:GetBoneMatrix(idxPelvis)
        return lowPos, highMat
    elseif strategy == AlignStrategy.FEET_TO_HEAD then
        local idxL = ent:LookupBone(BONE_L_FOOT)
        local idxR = ent:LookupBone(BONE_R_FOOT)
        local idxHead = ent:LookupBone(BONE_HEAD)
        if not idxL or not idxR or not idxHead then
            return nil, nil
        end
        local posL, _ = ent:GetBonePosition(idxL)
        local posR, _ = ent:GetBonePosition(idxR)
        local lowPos = (posL + posR) * 0.5
        local highMat = ent:GetBoneMatrix(idxHead)
        return lowPos, highMat
    else
        return nil, nil
    end
end

--- 提供基于骨骼策略的刚体对齐算法，用于将一个实体（通常是动画器）
--- 对齐到另一个实体（通常是布娃娃）的特定骨骼区间。
--- 核心思路：
--- 1. 根据选定策略，从源实体和目标实体获取低点位置和高点骨骼矩阵。
--- 2. 基于低点位置和高点方向构建正交局部坐标系矩阵。
--- 3. 计算源坐标系到目标坐标系的变换矩阵（目标 * 源逆矩阵）。
--- 4. 从变换矩阵中提取位置、旋转、均匀缩放并应用到源实体。
--- @param source Entity 接受变换的实体，通常是动画器 (prop_dynamic)
--- @param target Entity 提供对齐参考的实体，通常是布娃娃 (prop_ragdoll)
--- @param strategy number 对齐策略，参见 AlignStrategy，默认为 FEET_TO_HEAD
--- @return boolean ok 对齐是否成功
local function alignRagdoll(source, target, strategy)
    if not IsValid(source) or not IsValid(target) then
        return false
    end

    strategy = strategy or AlignStrategy.FEET_TO_HEAD

    local lowPosSource, highMatSource = getBoneData(source, strategy)
    local lowPosTarget, highMatTarget = getBoneData(target, strategy)

    if not lowPosSource or not highMatSource or not lowPosTarget or not highMatTarget then
        return false
    end

    local function BuildMatrix(lowPos, highMat)
        local highPos = highMat:GetTranslation()
        local vec = highPos - lowPos
        local len = vec:Length()

        if len == 0 then
            return nil
        end

        local zAxis = vec:GetNormalized()
        local xAxis = highMat:GetRight():GetNormalized()
        xAxis = (xAxis - zAxis * xAxis:Dot(zAxis)):GetNormalized()
        local yAxis = zAxis:Cross(xAxis):GetNormalized()

        local M = Matrix()
        M:SetTranslation(lowPos)
        M:SetForward(zAxis)
        M:SetRight(xAxis)
        M:SetUp(yAxis)
        M:SetScale(Vector(len, len, len))
        return M
    end

    local matrixSource = BuildMatrix(lowPosSource, highMatSource)
    local matrixTarget = BuildMatrix(lowPosTarget, highMatTarget)

    if not matrixSource or not matrixTarget then
        return false
    end

    local matrixSourceInv = Matrix()
    matrixSourceInv:Set(matrixSource)
    if not matrixSourceInv:Invert() then
        return false
    end

    local matrixTransform = Matrix()
    matrixTransform:Set(matrixTarget)
    matrixTransform:Mul(matrixSourceInv)

    local newPos = matrixTransform:GetTranslation()
    local newAng = matrixTransform:GetAngles()
    local newScaleVec = matrixTransform:GetScale()
    local scaleFactor = newScaleVec.x

    source:SetModelScale(scaleFactor, 0)
    source:SetPos(newPos)
    source:SetAngles(Angle(0, newAng.yaw, 0))

    return true
end

local function createAnimatorFollower(ragdoll, animator)
    local follower = ents.Create("prop_sphere")
    follower:SetKeyValue("radius", 12)
    follower:SetModel("models/dav0r/hoverball.mdl")
    follower:SetCollisionGroup(COLLISION_GROUP_DEBRIS) -- COLLISION_GROUP_NONE if not set to COLLISION_GROUP_DEBRIS
    follower:SetCustomCollisionCheck(true)             -- can work together with SetCollisionGroup

    follower.EPDACustomEntFlag = true

    follower:SetPos(animator:GetPos())
    follower:SetAngles(animator:GetAngles())

    follower:Spawn()
    return follower
end

local function createAnimator(ragdoll)
    local animator = ents.Create("prop_dynamic")
    animator:SetKeyValue("solid", 0) -- Not solid
    animator:SetModel("models/brutal_deaths/model_anim_modify.mdl")
    animator:SetBodygroup(animator:FindBodygroupByName("barney"), 1)

    local ok = alignRagdoll(animator, ragdoll, AlignStrategy.FEET_TO_HEAD)
        or alignRagdoll(animator, ragdoll, AlignStrategy.FEET_TO_PELVIS)
        or alignRagdoll(animator, ragdoll, AlignStrategy.PELVIS_TO_HEAD)

    if not ok then
        return nil
    end

    animator:Spawn()
    return animator
end

local function createRagdoll(ply)
    local ragdoll = ents.Create("prop_ragdoll")
    ragdoll:SetModel(ply:GetModel())

    ragdoll.EPDACustomEntFlag = true
    ragdoll.EPDAOwner = ply

    ragdoll:SetPos(ply:GetPos())
    ragdoll:SetAngles(ply:GetAngles())

    ragdoll:Spawn()
    return ragdoll
end

local function CreateProps(ply)
    local ragdoll = createRagdoll(ply)
    if not IsValid(ragdoll) then
        return nil
    end

    local animator = createAnimator(ragdoll)
    if not IsValid(animator) then
        ragdoll:Remove()
        return nil
    end

    local follower = createAnimatorFollower(ragdoll, animator)
    if not IsValid(follower) then
        ragdoll:Remove()
        animator:Remove()
        return nil
    end

    return {
        ragdoll = ragdoll,
        animator = animator,
        follower = follower,
    }
end

hook.Add("ShouldCollide", "ShouldCollide_EPDA_FakeDeathProps", function(ent1, ent2)
    return not (ent1.EPDACustomEntFlag and ent2.EPDACustomEntFlag)
end)

return CreateProps
