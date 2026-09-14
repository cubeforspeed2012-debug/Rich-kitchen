--!nonstrict
-- HE WILL COME v3 - все настройки. Стады / секунды.

local GameConfig = {}

GameConfig.Rooms = {
	MaxPlayers = 4,
	MaxRooms = 4,
	ArenaSpacing = 1600,
	ArenaBaseOffset = Vector3.new(2000, 0, 0),
	LobbyCenter = Vector3.new(0, 0, 0),
}

-- Бег бесконечный. Подкат - главный инструмент: ужимает персонажа, чтобы пролезть в щель.
GameConfig.Movement = {
	WalkSpeed = 14,
	SprintSpeed = 24,
	SlideSpeed = 46,
	SlideDuration = 0.7,
	SlideCooldown = 1.2,
	SlideHeightScale = 0.42,   -- рост в подкате ~2.8 стада; щель 4 стада, стоя (5+) не пролезть
}

GameConfig.Noise = {
	Sprint = 44,
	SprintInterval = 0.4,
	Walk = 12,
	Slide = 28,
	Key = 32,
	Locker = 22,
	Shout = 2000,
	ShoutCooldown = 8,
}

GameConfig.Monster = {
	Scale = 2.2,               -- киллер большой: ~20 стадов ростом
	PatrolSpeed = 13,
	InvestigateSpeed = 18,
	ChaseSpeed = 27,           -- быстрее твоего бега: спасают только щели, углы и шкафы
	SpeedPerKey = 0.8,
	SightRange = 60,
	SightRangeFlashlight = 100,
	FieldOfView = 100,
	CloseSense = 12,
	CatchDistance = 6.5,
	LoseSightGrace = 3,
	SearchTime = 6,
	RepathInterval = 0.4,
	ScreamCooldown = 12,
	CatchCooldown = 3,
	LockerPullGrace = 1.5,
}

GameConfig.Match = {
	PrepTime = 20,
	KeysRequired = 5,
	KeyHoldTime = 1,
	ReviveTime = 4,
	BleedOutTime = 40,
	EndScreenTime = 7,
	MaxMatchTime = 900,
	DimLights = 0.3,
}

GameConfig.Map = {
	TileSize = 6,
	WallHeight = 20,
	SlitHeight = 4,
}

return GameConfig
