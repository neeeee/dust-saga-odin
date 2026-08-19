package systems

// Mirrors packages/shared/src/constants/game.ts — the tuning knobs the
// gameplay loop and the network send-rate depend on. Kept in one place so
// the Odin client stays in lock-step with the server's expectations.

GAME_CONFIG :: struct {
	TICK_RATE:                int,
	PLAYER_SPEED:             f32,
	MAX_HEALTH:               int,
	VIEW_DISTANCE:            f32,
	INTERPOLATION_DELAY_MS:   int,
	ATTACK_RANGE:             f32,
	RANGED_ATTACK_RANGE:      f32,
	MANUAL_ATTACK_RANGE:      f32,
	MANUAL_ATTACK_CONE_ANGLE: f32,
	MAX_INVENTORY_SLOTS:      int,
	MAX_LEVEL:                int,
	MAX_POSITION:             f32,
}

GAME :: GAME_CONFIG {
	TICK_RATE                = 30,
	PLAYER_SPEED             = 5.5,
	MAX_HEALTH               = 100,
	VIEW_DISTANCE            = 50.0,
	INTERPOLATION_DELAY_MS   = 100,
	ATTACK_RANGE             = 2.5,
	RANGED_ATTACK_RANGE      = 15.0,
	MANUAL_ATTACK_RANGE      = 3.5,
	MANUAL_ATTACK_CONE_ANGLE = 1.5707963, // PI/2
	MAX_INVENTORY_SLOTS      = 64,
	MAX_LEVEL                = 60,
	MAX_POSITION             = 500.0,
}

COMBAT_CONFIG :: struct {
	AUTO_ATTACK_BASE_COOLDOWN: f64, // ms
	AUTO_ATTACK_MIN_COOLDOWN:  f64, // ms
	MANUAL_ATTACK_COOLDOWN:    f64, // ms
	CRITICAL_CHANCE:           f32,
	CRITICAL_MULTIPLIER:       f32,
}

COMBAT :: COMBAT_CONFIG {
	AUTO_ATTACK_BASE_COOLDOWN = 3000.0,
	AUTO_ATTACK_MIN_COOLDOWN  = 1000.0,
	MANUAL_ATTACK_COOLDOWN    = 2000.0,
	CRITICAL_CHANCE           = 0.1,
	CRITICAL_MULTIPLIER       = 2.0,
}

NETWORK_CONFIG :: struct {
	HEARTBEAT_INTERVAL_MS:    f64,
	CONNECTION_TIMEOUT_MS:    f64,
	MAX_RECONNECT_ATTEMPTS:   int,
	RECONNECT_DELAY_MS:       f64,
	RECONNECT_DELAY_MAX_MS:   f64,
	RECONNECT_BACKOFF_FACTOR: f64,
	MOVEMENT_SEND_RATE_MS:    f64, // min gap between PLAYER_MOVE sends
	POLLING_INTERVAL_MS:      f64, // long-poll cycle duration (ms)
	POLLING_TIMEOUT_MS:       f64, // how long to wait per poll before retrying
	MAX_PENDING_SEND:         int, // cap on packets buffered while disconnected
}

NET :: NETWORK_CONFIG {
	HEARTBEAT_INTERVAL_MS    = 30000.0,
	CONNECTION_TIMEOUT_MS    = 10000.0,
	MAX_RECONNECT_ATTEMPTS   = 20,
	RECONNECT_DELAY_MS       = 1000.0,
	RECONNECT_DELAY_MAX_MS   = 30000.0,
	RECONNECT_BACKOFF_FACTOR = 1.5,
	MOVEMENT_SEND_RATE_MS    = 50.0,
	POLLING_INTERVAL_MS      = 20000.0,
	POLLING_TIMEOUT_MS       = 20000.0,
	MAX_PENDING_SEND         = 128,
}

// Culling thresholds live in culling.odin (declared there first).

// Default server address. The TS client defaults to http://localhost:3001.
DEFAULT_SERVER_URL :: "http://localhost:3001"
DEFAULT_SERVER_HOST :: "localhost"
DEFAULT_SERVER_PORT :: 3001
