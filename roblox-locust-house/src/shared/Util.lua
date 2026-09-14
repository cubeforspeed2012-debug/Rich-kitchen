--!nonstrict
-- Маленькие помощники, которые нужны и серверу, и клиенту.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Util = {}

function Util.getRoot(character: Instance?): BasePart?
	if not character then
		return nil
	end
	return (character :: Instance):FindFirstChild("HumanoidRootPart") :: BasePart?
end

function Util.getHumanoid(character: Instance?): Humanoid?
	if not character then
		return nil
	end
	return (character :: Instance):FindFirstChildOfClass("Humanoid")
end

function Util.isAlive(player: Player): boolean
	local humanoid = Util.getHumanoid(player.Character)
	return humanoid ~= nil and humanoid.Health > 0
end

-- Есть ли прямая видимость между двумя точками (стены мешают, персонажи - нет).
function Util.hasLineOfSight(fromPos: Vector3, toPos: Vector3, ignore: { Instance }): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true

	local direction = toPos - fromPos
	local result = Workspace:Raycast(fromPos, direction, params)
	if not result then
		return true
	end
	-- Попали в персонажа - считаем, что видим.
	local model = result.Instance:FindFirstAncestorOfClass("Model")
	if model and Players:GetPlayerFromCharacter(model) then
		return true
	end
	return false
end

-- Ближайший живой игрок к точке.
function Util.closestPlayer(position: Vector3, maxDistance: number): (Player?, number)
	local best: Player? = nil
	local bestDist = maxDistance
	for _, player in Players:GetPlayers() do
		local root = Util.getRoot(player.Character)
		if root and Util.isAlive(player) then
			local dist = (root.Position - position).Magnitude
			if dist < bestDist then
				best = player
				bestDist = dist
			end
		end
	end
	return best, bestDist
end

function Util.clamp(value: number, min: number, max: number): number
	return math.max(min, math.min(max, value))
end

return Util
