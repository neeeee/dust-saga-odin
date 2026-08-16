import express from 'express';
import { createServer } from 'http';
import { existsSync } from 'fs';
import { join } from 'path';
import { NetworkServer } from './core/network/NetworkServer';
import { DatabaseManager } from './core/database/DatabaseManager';
import { createApiRouter } from './core/api';

const app = express();
const httpServer = createServer(app);
const PORT = process.env.PORT || 3001;

app.use(express.json());

app.get('/health', (_req, res) => {
  const db = DatabaseManager.getInstance();
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    database: db.isPostgresConnected() ? 'connected' : 'disconnected',
    redis: db.isRedisConnected() ? 'connected' : 'disconnected'
  });
});

app.get('/api/classes', (_req, res) => {
  const { CLASS_DEFINITIONS } = require('@dust-saga/shared');
  res.json(CLASS_DEFINITIONS);
});

async function startServer() {
  try {
    console.log('Starting Dust Saga Server...');

    const db = DatabaseManager.getInstance();
    await db.connect();

    if (db.isPostgresConnected()) {
      await db.initializeSchema();
    } else {
      console.log('Running in development mode without database');
    }

    const networkServer = new NetworkServer(httpServer, {
      redis: db.redis,
      isRedisConnected: () => db.isRedisConnected(),
    });

    await networkServer.questSys.initialize(db);
    await networkServer.cutsceneSys.initialize(db);
    await networkServer.itemSys.initialize(db);

    // ── HTTP API ───────────────────────────────────────────────────────────
    // All gameplay/admin REST routes live under packages/server/src/core/api.
    // Resolve the systems once here and hand them to the router tree; route
    // handlers receive their dependencies instead of reaching into singletons.
    app.use('/api', createApiRouter({
      questSys: networkServer.questSys,
      cutsceneSys: networkServer.cutsceneSys,
      itemSys: networkServer.itemSys,
    }));

    // ── API management dashboard ───────────────────────────────────────────
    // The Vue SPA under src/core/apiManagementClient is built (`npm run
    // admin:build`) into its `dist` folder and served at /admin. The lookup
    // checks a few candidate locations so it resolves correctly both when
    // running under tsx (src layout) and as a compiled `node dist` build.
    // If the build is absent the route is simply skipped — run `admin:dev`
    // for the Vite dev server with live HMR instead.
    const adminCandidates = [
      join(__dirname, 'core/apiManagementClient/dist'),
      join(__dirname, '../src/core/apiManagementClient/dist'),
      join(process.cwd(), 'src/core/apiManagementClient/dist'),
    ];
    const adminDist = adminCandidates.find(p => existsSync(p));
    if (adminDist) {
      app.use('/admin', express.static(adminDist));
      app.get('/admin/*', (_req, res) => res.sendFile(join(adminDist, 'index.html')));
      console.log(`API management dashboard served at http://localhost:${PORT}/admin`);
    } else {
      console.log('API management dashboard not built — run `npm run admin:dev` or `npm run admin:build`');
    }

    // B2: attach the Socket.IO Redis adapter when Redis is available so zone-room
    // broadcasts propagate across processes (enables future multi-shard). In
    // single-process / no-Redis mode the default in-memory adapter is used.
    let adapterPub: import('redis').RedisClientType | null = null;
    let adapterSub: import('redis').RedisClientType | null = null;
    // B5: dedicated subscribe client for the packet relay (sendToPlayer routing).
    let relaySub: import('redis').RedisClientType | null = null;
    // B4: dedicated subscribe client for cross-shard party state sync.
    let partySub: import('redis').RedisClientType | null = null;
    if (db.isRedisConnected()) {
      try {
        adapterPub = db.createRedisClient();
        adapterSub = db.createRedisClient();
        await adapterPub.connect();
        await adapterSub.connect();
        networkServer.useRedisAdapter(adapterPub, adapterSub);

        relaySub = db.createRedisClient();
        await relaySub.connect();
        await networkServer.usePacketRelay(relaySub);

        partySub = db.createRedisClient();
        await partySub.connect();
        await networkServer.usePartySync(partySub);
      } catch (err) {
        console.warn('Redis adapter/relay/party-sync disabled (continuing single-process):', err);
        if (adapterPub) await adapterPub.quit().catch(() => {});
        if (adapterSub) await adapterSub.quit().catch(() => {});
        if (relaySub) await relaySub.quit().catch(() => {});
        if (partySub) await partySub.quit().catch(() => {});
        adapterPub = null;
        adapterSub = null;
        relaySub = null;
        partySub = null;
      }
    } else {
      console.log('Redis not connected — running with in-memory Socket.IO adapter (single-process)');
    }

    networkServer.getSpawnManager().initialize();
    networkServer.populateEnemySpatialHash();
    console.log('World spawned');

    // B6: claim this shard's zones in Redis so cross-shard handoff can route
    // zone transitions to the owning shard. In single-process mode (no
    // ZONE_OWNERSHIP env) all zones are claimed; the handoff branch in
    // handleEnterZone is never taken because getOwner() returns the local shard.
    const { ZONE_DATABASE } = require('@dust-saga/shared');
    const allZoneIds = Object.keys(ZONE_DATABASE);
    await networkServer.zoneOwnership.claimZones(allZoneIds).catch(() => {});

    const tickRate = networkServer.getTickRate();
    const tickInterval = 1000 / tickRate;
    let lastTick = process.hrtime.bigint();

    function tick() {
      const now = process.hrtime.bigint();
      const elapsedMs = Number(now - lastTick) / 1_000_000;
      lastTick = now;

      networkServer.gameLoop(Math.min(elapsedMs, 200));

      const nextDelay = Math.max(0, tickInterval - Number(process.hrtime.bigint() - now) / 1_000_000);
      setTimeout(tick, nextDelay);
    }
    setTimeout(tick, tickInterval);

    setInterval(() => {
      networkServer.saveAllCharacters().catch(err => console.error('Autosave error:', err));
    }, 60000);

    // B3: refresh presence TTLs so live players' entries don't expire while the
    // shard is healthy (entries auto-expire within 60s if the shard crashes).
    const presenceHeartbeat = setInterval(() => {
      networkServer.presence.heartbeat().catch(err => console.error('Presence heartbeat error:', err));
    }, 20000);
    presenceHeartbeat.unref();

    httpServer.listen(PORT, () => {
      console.log(`Server running on http://localhost:${PORT}`);
      console.log(`WebSocket server ready`);
    });

    process.on('SIGINT', async () => {
      console.log('\nShutting down server...');
      await networkServer.saveAllCharacters();
      await networkServer.zoneOwnership.releaseZones().catch(() => {});
      await networkServer.stopPacketRelay().catch(() => {});
      await networkServer.stopPartySync().catch(() => {});
      if (adapterPub) await adapterPub.quit().catch(() => {});
      if (adapterSub) await adapterSub.quit().catch(() => {});
      await db.disconnect();
      httpServer.close();
      process.exit(0);
    });

  } catch (error) {
    console.error('Failed to start server:', error);
    process.exit(1);
  }
}

startServer();
