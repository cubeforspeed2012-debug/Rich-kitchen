--!nonstrict
-- HE WILL COME v2 - все настройки игры. Комментарии на русском, числа в стадах/секундах.

local GameConfig = {}

GameConfig.Rooms = {
	MaxPlayers = 4,            -- больше 4 в комнату не пустит
	MaxRooms = 4,              -- комнат одновременно на одном сервере
	ArenaSpacing = 1200,       -- расстояние между аренами разных комнат
	ArenaBaseOffset = Vector3.new(1500, 0, 0),
	LobbyCenter = Vector3.new(0, 0, 0),
}

GameConfig.Movement = {
	WalkSpeed = 14,
	SprintSpeed = 24,
	CrouchSpeed = 7,
	MaxStamina = 100,
	SprintDrain = 14,          -- полной шкалы хватает на ~7 секунд бега
	StaminaRegen = 9,
	RegenDelay = 1.5,
	MinSprintStamina = 5,
	SlideSpeed = 42,
	SlideDuration = 0.55,
	SlideCooldown = 3,
	SlideStamina = 20,
	SlideHeightScale = 0.5,
}

-- радиус, с которого монстр слышит действие
GameConfig.Noise = {
	Sprint = 42,
	SprintInterval = 0.4,
	Walk = 12,
	Crouch = 0,                -- крадёшься - не слышно вообще
	Slide = 30,
	Search = 36,               -- шаришь по парте - шумно
	Locker = 22,
	Shout = 1000,              -- крик слышно по всей школе
	ShoutCooldown = 8,
}

GameConfig.Monster = {
	PatrolSpeed = 12,
	InvestigateSpeed = 17,
	ChaseSpeed = 25.5,         -- чуть быстрее спринта: убегать надо умно, а не по прямой
	SpeedPerKey = 0.9,         -- за каждый найденный ключ он становится быстрее
	SightRange = 55,
	SightRangeFlashlight = 95, -- с включённым фонарём тебя видно издалека
	FieldOfView = 100,
	CloseSense = 9,            -- вплотную чует без обзора
	CatchDistance = 4,
	LoseSightGrace = 3,        -- столько секунд помнит тебя без прямой видимости
	SearchTime = 6,
	RepathInterval = 0.4,
	ScreamCooldown = 12,       -- заметив игрока, орёт на всю школу
	CatchCooldown = 3,
	LockerPullGrace = 1.5,     -- видел, как ты прыгнул в шкаф - вытащит
}

GameConfig.Match = {
	PrepTime = 20,             -- свет горит, монстр ещё спит
	KeysRequired = 5,
	SearchHoldTime = 2.5,
	SearchCooldown = 1,
	ReviveTime = 4,
	BleedOutTime = 40,
	EndScreenTime = 7,
	MaxMatchTime = 720,
	DimLights = 0.28,          -- яркость ламп после прихода монстра
}

GameConfig.Map = {
	WallHeight = 12,
	TileSize = 4,
}

return GameConfig
