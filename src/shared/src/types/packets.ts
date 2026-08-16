export enum PacketType {
  CONNECT = 0,
  DISCONNECT = 1,
  HEARTBEAT = 2,

  LOGIN = 10,
  REGISTER = 11,
  AUTH_SUCCESS = 12,
  AUTH_FAILURE = 13,
  CHARACTER_LIST = 14,
  CHARACTER_CREATE = 15,
  CHARACTER_SELECT = 16,
  CHARACTER_DELETE = 17,

  PLAYER_MOVE = 20,
  PLAYER_POSITION_UPDATE = 21,
  PLAYER_ROTATION_UPDATE = 22,
  WORLD_STATE = 23,

  ATTACK = 30,
  MANUAL_ATTACK = 36,
  DAMAGE = 31,
  HEAL = 32,
  DEATH = 33,
  SKILL_USE = 34,
  COOLDOWN_UPDATE = 35,

  CHAT_MESSAGE = 40,

  ENTER_ZONE = 50,
  LEAVE_ZONE = 51,
  ENTITY_SPAWN = 52,
  ENTITY_DESPAWN = 53,
  ENEMY_STATE_CHANGE = 54,

  INVENTORY_UPDATE = 60,
  ITEM_USE = 61,
  ITEM_DROP = 62,
  ITEM_PICKUP = 63,
  EQUIP_ITEM = 64,
  UNEQUIP_ITEM = 65,
  LOOT_SPAWN = 66,
  LOOT_PICKUP = 67,

  QUEST_LIST = 70,
  QUEST_ACCEPT = 71,
  QUEST_PROGRESS = 72,
  QUEST_COMPLETE = 73,
  QUEST_ABANDON = 74,

  NPC_INTERACT = 80,
  NPC_DIALOG = 81,
  NPC_SHOP = 82,
  NPC_SHOP_BUY = 83,
  NPC_SHOP_SELL = 84,
  NPC_DIALOG_CLOSE = 85,

  STATS_UPDATE = 90,
  EXPERIENCE_GAIN = 91,
  LEVEL_UP = 92,
  STAT_ALLOCATE = 93,
  JOB_ADVANCE = 94,
  SKILL_BAR_UPDATE = 95,
  STATUS_EFFECT_UPDATE = 96,
  ENTITY_STATUS_EFFECTS = 97,
  SONG_PULSE = 98,
  SKILL_ALLOCATE = 99,
  RESPAWN_REQUEST = 100,
  REVIVE_PLAYER = 130,
  PLAYER_REVIVED = 131,

  NOTIFICATION = 101,
  ERROR = 102,

  PARTY_CREATE_REQUEST = 110,
  PARTY_INVITE_REQUEST = 111,
  PARTY_INVITE = 112,
  PARTY_JOIN_REQUEST = 113,
  PARTY_JOIN_RESPONSE = 114,
  PARTY_LEAVE = 115,
  PARTY_DISBAND = 116,
  PARTY_KICK = 117,
  PARTY_UPDATE = 118,
  PARTY_LOOT_ROLL = 119,
  PARTY_LOOT_RESULT = 120,
  PARTY_PROMOTE = 121,

  WEAPON_ENHANCE = 140,
  ENHANCEMENT_RESULT = 141,
  AOE_ENTITY = 150,
  AOE_DESPAWN = 151,

  TRADE_REQUEST = 160,
  TRADE_INVITE = 161,
  TRADE_RESPONSE = 162,
  TRADE_OPEN = 163,
  TRADE_ADD_ITEM = 164,
  TRADE_REMOVE_ITEM = 165,
  TRADE_SET_GOLD = 166,
  TRADE_UPDATE = 167,
  TRADE_ACCEPT = 168,
  TRADE_CANCEL = 169,
  TRADE_CLOSE = 170,

  BATCH_COMBAT = 171,
  ZONE_HANDOFF = 172,
  PLAYER_REST = 173,
  SKILL_CANCEL = 174,
  ENTITY_ANIMATION = 175,
  RETURN_TO_CHARACTER_SELECT = 176,
  LOGOUT = 177,

  LOOT_OPEN = 178,
  LOOT_DESPAWN = 179,
  LOOT_TAKE = 180,
  PARTY_LOOT_RULE_CHANGE = 181,
  PARTY_LOOT_ROLL_SUBMIT = 182,
  RECIPE_LEARN = 183,
  CRAFT_REQUEST = 184,
  CRAFT_RESULT = 185,

  CUTSCENE_START = 186,
  CUTSCENE_COMPLETE = 187,
  CUTSCENE_END = 188,
  FLOATING_TEXT = 189,
}

export interface Packet {
  type: PacketType;
  timestamp: number;
  data: any;
}

export interface PositionData {
  x: number;
  y: number;
  z: number;
}

export interface RotationData {
  x: number;
  y: number;
  z: number;
  w: number;
}

export interface MovementData {
  velocityX: number;
  velocityY: number;
  velocityZ: number;
  speed: number;
  direction: number;
}

export interface PlayerData {
  id: string;
  name: string;
  position: PositionData;
  rotation: RotationData;
  level: number;
  health: number;
  maxHealth: number;
}

export interface EntityData {
  id: string;
  type: 'player' | 'npc' | 'enemy' | 'item' | 'loot' | 'aoe' | 'summon';
  position: PositionData;
  rotation: RotationData;
  data: any;
}
