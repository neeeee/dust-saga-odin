export interface ZoneSpawn {
    enemyType: string;
    count: number;
    spawnArea: {
        centerX: number;
        centerZ: number;
        radius: number;
    };
    patrolPoints?: Array<{
        x: number;
        y: number;
        z: number;
    }>;
}
export declare enum ZoneType {
    SAFE = "safe",
    PVE = "pve",
    PVP = "pvp",
    NATION = "nation",
    WAR = "war",
    DUNGEON = "dungeon"
}
export interface ZoneDefinition {
    id: string;
    name: string;
    description: string;
    type: ZoneType;
    levelRange: [number, number];
    groundColor: {
        r: number;
        g: number;
        b: number;
    };
    fogColor: {
        r: number;
        g: number;
        b: number;
    };
    fogDensity: number;
    size: number;
    playerSpawn: {
        x: number;
        y: number;
        z: number;
    };
    spawns: ZoneSpawn[];
    connections: string[];
    environmentObjects: Array<{
        type: 'tree' | 'rock' | 'bush' | 'house';
        positions: Array<{
            x: number;
            y: number;
            z: number;
            scale?: number;
            rotation?: number;
        }>;
    }>;
    nation?: 'varik' | 'pfelstein' | 'latugan';
    isPvpEnabled: boolean;
    musicTrack?: string;
    /** If false, the zone requires unlocking via a quest's `unlocksZones` field. */
    unlockedByDefault?: boolean;
}
export declare const ZONE_DATABASE: Record<string, ZoneDefinition>;
export declare function getZoneDefinition(id: string): ZoneDefinition | undefined;
export declare function isZonePvpEnabled(zoneId: string): boolean;
export declare const NATION_ZONE_MAP: Record<string, {
    nation: 'varik' | 'pfelstein' | 'latugan';
    zoneId: string;
    borderZoneId: string;
}>;
