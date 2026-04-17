-- EPDA CreateRagdoll Tester
-- 左键：调用 Player:CreateRagdoll 创建布娃娃并保存引用
-- 右键：移除上一个创建的布娃娃



TOOL.Category = "EPDA"
TOOL.Name = "CreateRagdoll Tester"

if SERVER then
    util.AddNetworkString("EPDA_Ragdoll")
end

function TOOL:LeftClick(tr)
    local ply = self:GetOwner()
    -- ply:SetNoDraw(true)

    print("CollisionGroup: " .. ply:GetCollisionGroup())

    ply:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
    ply:SetModelScale(0.1, 0)
    -- ply:SetNotSolid(true)
    ply:GodEnable()

    local props = include("modules/fake_death_props.lua")(ply)

    net.Start("EPDA_Ragdoll")
    net.WriteEntity(props.ragdoll)
    net.Send(ply)
    return true
end

function TOOL:RightClick(tr)
    local ply = self:GetOwner()
    -- ply:SetNoDraw(false)

    ply:SetCollisionGroup(COLLISION_GROUP_PLAYER)
    ply:SetModelScale(1, 0)
    -- ply:SetNotSolid(false)
    ply:GodDisable()

    net.Start("EPDA_Ragdoll")
    net.WriteEntity(nil)
    net.Send(ply)
    return true
end

-- 工具切换或移除时不做自动清理（保留布娃娃）
function TOOL:Holster() return true end
