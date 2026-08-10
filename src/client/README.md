# Dust Saga — Odin client

A native desktop client for Dust Saga, written in [Odin](https://odin-lang.org)
with [raylib](https://www.raylib.com/). It speaks the exact same Socket.IO /
JSON protocol as the TypeScript server in `packages/server`, so the two are
fully interoperable — point this client at the server (default
`localhost:3001`) and play.

## Build & run

```bash
./build.sh           # debug build → ./dust_saga
./build.sh release   # optimized
./build.sh run       # build + immediately run
```

Requires the Odin compiler on PATH. The `vendor:raylib` collection ships with
Odin at `<odin>/vendor` and is found automatically.

Run it from the `src/client` directory (or set the working dir there) so the
`assets/maps/*.json` zone files resolve.

## Architecture

The client is split into a `systems` package (the engine/protocol layer) and
per-scene packages under `scenes/`:

```
src/client/
├─ main.odin                 # entry point + TITLE→LOGIN→CHAR_SELECT→GAMEPLAY state machine
├─ systems/                  # engine + protocol (no raylib window logic)
│  ├─ networkclient.odin     # Socket.IO v4 (Engine.IO v4) client over raw TCP+WebSocket,
│  │                         #   full 190-opcode PacketType enum, JSON packet framing
│  ├─ packet_handlers.odin   # inbound dispatch: WORLD_STATE / POS_UPDATE / SPAWN /
│  │                         #   DAMAGE / STATS / INVENTORY / CHAT / ... → Scene + Local_Player
│  ├─ json_helpers.odin      # typed accessors over core:encoding/json for polymorphic payloads
│  ├─ ecs.odin               # SoA entity Scene (transforms, renderables, interp buffers, culling)
│  ├─ types.odin             # Local_Player, Player_Stats, Inventory, Chat_Log, skill bar
│  ├─ input.odin             # WASD / sprint / F / Space / E / digits / Tab / Enter / mouse
│  ├─ interpolation.odin     # 150 ms ring-buffer snapshot interpolation
│  ├─ culling.odin           # interest radius + adaptive avatar cap
│  ├─ zone_defs.odin         # client map definition (mirrors assets/maps/*.json)
│  ├─ map_builder.odin       # load zone JSON, render ground/structures/trees/teleport pads
│  ├─ config.odin            # GAME_CONFIG / COMBAT_CONFIG / NETWORK_CONFIG (mirrors shared/)
│  └─ text.odin              # cstring-adapting DrawText/MeasureText wrappers
├─ scenes/
│  ├─ title_screen/          # main menu
│  ├─ login/                 # connect + LOGIN/REGISTER → AUTH_SUCCESS
│  ├─ character_select/      # CHARACTER_LIST, pick/create → CHARACTER_SELECT
│  └─ gameplay/              # 3rd-person loop: movement, combat, targeting, HUD, chat, inventory
└─ assets/
   ├─ maps/*.json            # zone geometry / props / teleporters (19 zones)
   └─ models/*.glb           # GLB assets (not yet wired into the procedural renderer)
```

## Protocol

The server is Socket.IO v4. Every message is a JSON `{type, timestamp, data}`
object emitted on the `"packet"` event, where `type` is the numeric
`PacketType` (see `systems/networkclient.odin` for the full enum, mirrored from
`packages/shared/src/types/packets.ts`). Auth is application-layer (the
`LOGIN` packet), not part of the Socket.IO handshake, so the client connects
directly to the websocket transport (`EIO=4&transport=websocket`).

## Rendering

Currently procedural primitives — capsule entities, box structures, generated
trees/rocks, ground planes, teleport pads. GLB model loading is stubbed for a
follow-up; the asset pipeline and model catalog under `assets/models/` are
ready for it.

## State scope

This pass implements the core gameplay loop: connect, authenticate, character
select, enter zone, walk around (with server reconciliation), see other
entities move (interpolated), target/attack, use the skill bar, chat, view
inventory, and transition zones via teleport pads. Party / trade / craft /
quest / enhancement / cutscene panels are out of scope for this pass and left
for follow-up.
