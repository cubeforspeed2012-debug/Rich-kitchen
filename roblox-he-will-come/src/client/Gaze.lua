--!nonstrict
-- Раз в 0.2 секунды отправляем серверу, куда смотрит камера.
-- Именно по этому серверу понимает, держишь ли ты ЕГО взглядом.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("HWCShared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local gazeEvent = Remotes.get("GazeReport")

local Gaze = {}

function Gaze.start()
	task.spawn(function()
		while true do
			task.wait(0.2)
			local camera = Workspace.CurrentCamera
			if camera then
				gazeEvent:FireServer(camera.CFrame.Position, camera.CFrame.LookVector)
			end
		end
	end)
end

return Gaze
