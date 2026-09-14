--!nonstrict
-- Общие помощники.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Util = {}

function Util.getRoot(character): BasePart?
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart")
end

function Util.getHumanoid(character): Humanoid?
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

function Util.isAlive(player: Player): boolean
	local humanoid = Util.getHumanoid(player.Character)
	return humanoid ~= nil and humanoid.Health > 0
end

function Util.hasLineOfSight(fromPos: Vector3, toPos: Vector3, ignore): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true

	local result = Workspace:Raycast(fromPos, toPos - fromPos, params)
	if not result then
		return true
	end
	local model = result.Instance:FindFirstAncestorOfClass("Model")
	if model and Players:GetPlayerFromCharacter(model) then
		return true
	end
	return false
end

function Util.makePart(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = position
	part.Anchored = true
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

function Util.shuffle(list)
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = math.random(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

return Util
