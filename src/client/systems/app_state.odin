package systems

App_State :: enum {
	TITLE,
	LOGIN,
	CHARACTER_SELECT,
	LOADING,
	GAMEPLAY,
	CLOSING,
}

// Sentinel returned by the gameplay scene when the user logs out / returns to
// the character-select screen. main maps this onto .CHARACTER_SELECT.
CHARACTER_SELECT_NEEDED :: App_State.CHARACTER_SELECT
