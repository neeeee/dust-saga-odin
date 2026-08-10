package systems

// import rl "vendor:raylib"

INTEREST_RADIUS_SQ :: f32(60.0 * 60.0)
SHADOW_RADIUS_SQ :: f32(30.0 * 30.0)

cull_and_sort :: proc(s: ^Scene, player_pos: [3]f32, current_fps: int) {
	// 1. Update horizontal distance² from the local player to each entity.
	for i in 0 ..< s.count {
		dx := s.transforms[i].position.x - player_pos[0]
		dz := s.transforms[i].position.z - player_pos[2]
		s.dist_sq_to_player[i] = dx * dx + dz * dz
	}

	// 2. Adaptive Avatar Cap (Direct translation of TS logic)
	if current_fps < 58 {
		s.dynamic_avatar_cap = max(24, s.dynamic_avatar_cap - 2)
	} else if current_fps > 60 {
		s.dynamic_avatar_cap = min(150, s.dynamic_avatar_cap + 1)
	}

	// 3. Apply Culling flags
	// Note: For a proper sort, you'd radix sort the indices by dist_sq,
	// but for this example, we'll do a simple loop.
	avatars_rendered := 0
	player_idx := find_index(s, s.player_id)

	for i in 0 ..< s.count {
		is_player := (i == player_idx)
		is_player_entity := s.metas[i].kind == .PLAYER
		dist_sq := s.dist_sq_to_player[i]

		// Interest Management — never cull other players.
		if dist_sq > INTEREST_RADIUS_SQ && !is_player && !is_player_entity {
			s.is_frozen[i] = true
			s.casts_shadow[i] = false
			continue
		}

		s.is_frozen[i] = false

		// Shadow Culling
		s.casts_shadow[i] = (dist_sq < SHADOW_RADIUS_SQ) || is_player

		// Avatar Cap Culling
		if !is_player {
			if avatars_rendered >= s.dynamic_avatar_cap {
				s.is_frozen[i] = true // Freeze meshes outside the cap
				continue
			}
			avatars_rendered += 1
		}
	}
}
