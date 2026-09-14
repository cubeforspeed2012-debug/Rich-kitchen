--!nonstrict
-- Клиент раз в 0.2 сек присылает, куда смотрит камера. Здесь мы это храним и проверяем.

local GazeTracker = {}

local data = {}

function GazeTracker.set(player: Player, cameraPosition: Vector3, lookVector: Vector3)
	if typeof(cameraPosition) ~= "Vector3" or typeof(lookVector) ~= "Vector3" then
		return
	end
	if lookVector.Magnitude < 0.1 then
		return
	end
	-- камера не может быть далеко от самого игрока: отсекаем совсем грубую подделку
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - cameraPosition).Magnitude > 30 then
		return
	end
	data[player] = {
		position = cameraPosition,
		look = lookVector.Unit,
		time = os.clock(),
	}
end

function GazeTracker.get(player: Player)
	local entry = data[player]
	if not entry then
		return nil
	end
	-- данные старше секунды не считаем: игрок мог отвалиться
	if os.clock() - entry.time > 1 then
		return nil
	end
	return entry
end

function GazeTracker.clear(player: Player)
	data[player] = nil
end

return GazeTracker
