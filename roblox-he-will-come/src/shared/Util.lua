--!nonstrict
-- Мелкие помощники для сервера и клиента.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Util = {}

function Util.getRoot(character)
	return character and character:FindFirstChild("HumanoidRootPart") or nil
end

function Util.getHumanoid(character)
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

function Util.isAlive(player)
	local humanoid = Util.getHumanoid(player.Character)
	return humanoid ~= nil and humanoid.Health > 0
end

-- Нет ли стены между двумя точками. Персонажи игроков не считаются преградой.
function Util.hasLineOfSight(fromPos, toPos, ignore)
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

function Util.makePart(parent, name, size, position, color, material)
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

function Util.flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

return Util
