"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.PlayerSystem = void 0;
const EntityManager_1 = require("../EntityManager");
const shared_1 = require("@dust-saga/shared");
const obeliskBuff_1 = require("../../combat/obeliskBuff");
const shared_2 = require("@dust-saga/shared");
class PlayerSystem extends EntityManager_1.System {
    getGearBonuses(session) {
        const bonuses = { attack: 0, defense: 0, health: 0, mana: 0, speed: 0, STA: 0, STR: 0, AGI: 0, DEX: 0, SPI: 0, INT: 0, accuracy: 0, dodge: 0, attackSpeed: 0, castSpeed: 0, fireResist: 0, iceResist: 0, lightningResist: 0, poisonResist: 0, darkResist: 0, holyResist: 0, magicAttackPercent: 0, ailmentResist: 0, disorderResist: 0, criticalChance: 0, stunResist: 0, tripResist: 0, freezeResist: 0, burnResist: 0, curseResist: 0, bleedResist: 0, sleepResist: 0, weaknessResist: 0, weakenResist: 0, knockdownResist: 0, knockbackResist: 0, healPercent: 0 };
        for (const slot of Object.values(session.equipment)) {
            if (!slot)
                continue;
            const def = this.itemSys.getItemDefinition(slot.itemId);
            if (!def)
                continue;
            const s = def.stats;
            if (s.attack)
                bonuses.attack += s.attack;
            if (s.defense)
                bonuses.defense += s.defense;
            if (s.health)
                bonuses.health += s.health;
            if (s.mana)
                bonuses.mana += s.mana;
            if (s.speed)
                bonuses.speed += s.speed;
            if (s.STA)
                bonuses.STA += s.STA;
            if (s.STR)
                bonuses.STR += s.STR;
            if (s.AGI)
                bonuses.AGI += s.AGI;
            if (s.DEX)
                bonuses.DEX += s.DEX;
            if (s.SPI)
                bonuses.SPI += s.SPI;
            if (s.INT)
                bonuses.INT += s.INT;
            if (s.accuracy)
                bonuses.accuracy += s.accuracy;
            if (s.dodge)
                bonuses.dodge += s.dodge;
            if (s.attackSpeed)
                bonuses.attackSpeed += s.attackSpeed;
            if (s.castSpeed)
                bonuses.castSpeed += s.castSpeed;
            if (s.fireResist)
                bonuses.fireResist += s.fireResist;
            if (s.iceResist)
                bonuses.iceResist += s.iceResist;
            if (s.lightningResist)
                bonuses.lightningResist += s.lightningResist;
            if (s.poisonResist)
                bonuses.poisonResist += s.poisonResist;
            if (s.darkResist)
                bonuses.darkResist += s.darkResist;
            if (s.holyResist)
                bonuses.holyResist += s.holyResist;
            if (s.magicAttack)
                bonuses.magicAttackPercent += s.magicAttack;
            if (s.ailmentResist)
                bonuses.ailmentResist += s.ailmentResist;
            if (s.disorderResist)
                bonuses.disorderResist += s.disorderResist;
            if (s.stunResist)
                bonuses.stunResist += s.stunResist;
            if (s.tripResist)
                bonuses.tripResist += s.tripResist;
            if (s.freezeResist)
                bonuses.freezeResist += s.freezeResist;
            if (s.burnResist)
                bonuses.burnResist += s.burnResist;
            if (s.curseResist)
                bonuses.curseResist += s.curseResist;
            if (s.bleedResist)
                bonuses.bleedResist += s.bleedResist;
            if (s.sleepResist)
                bonuses.sleepResist += s.sleepResist;
            if (s.weaknessResist)
                bonuses.weaknessResist += s.weaknessResist;
            if (s.weakenResist)
                bonuses.weakenResist += s.weakenResist;
            if (s.knockdownResist)
                bonuses.knockdownResist += s.knockdownResist;
            if (s.knockbackResist)
                bonuses.knockbackResist += s.knockbackResist;
            if (s.criticalChance)
                bonuses.criticalChance += s.criticalChance;
            if (s.healPercent)
                bonuses.healPercent += s.healPercent;
            const enhanceLevel = slot.enhancementLevel || 0;
            if (enhanceLevel > 0) {
                const eqSlot = def.equipmentSlot;
                if (eqSlot === shared_2.EquipmentSlot.WEAPON) {
                    const isMagicWeapon = (s.magicAttack && s.magicAttack > 0) || (s.INT && s.INT > 0) || (s.SPI && s.SPI > 0);
                    if (!isMagicWeapon) {
                        bonuses.attack += enhanceLevel * 3;
                    }
                    if (isMagicWeapon) {
                        bonuses.magicAttackPercent += enhanceLevel * 0.02;
                    }
                }
                else if (eqSlot === shared_2.EquipmentSlot.ARMOR || eqSlot === shared_2.EquipmentSlot.HELMET || eqSlot === shared_2.EquipmentSlot.GLOVES || eqSlot === shared_2.EquipmentSlot.LEGS || eqSlot === shared_2.EquipmentSlot.SHIELD) {
                    bonuses.defense += enhanceLevel * 3;
                    bonuses.health += enhanceLevel * 15;
                }
                else if (eqSlot === shared_2.EquipmentSlot.BOOTS) {
                    bonuses.defense += enhanceLevel * 2;
                    bonuses.dodge += enhanceLevel * 1;
                }
            }
        }
        return bonuses;
    }
    constructor(entityManager) {
        super(entityManager);
        this.levelUpCallbacks = [];
    }
    onLevelUp(callback) {
        this.levelUpCallbacks.push(callback);
    }
    createSession(playerId, socketId, username, characterId, characterName, race, jobId, level, statPoints, unspentStatPoints, unspentSkillPoints, skillProficiencies, skillAdeptness, experience = 0) {
        const baseClass = (0, shared_2.getBaseClassForJob)(jobId);
        const stats = (0, shared_2.calculateDerivedStats)(race, jobId, level, statPoints);
        const xpToNext = (0, shared_2.getExperienceToNextLevel)(level);
        const designJobId = (0, shared_2.getDesignJobId)(jobId);
        const adeptness = skillAdeptness
            ? (typeof skillAdeptness === 'string' ? JSON.parse(skillAdeptness) : skillAdeptness)
            : (0, shared_2.createDefaultSkillAdeptness)(designJobId);
        return {
            playerId,
            socketId,
            username,
            characterId,
            characterName,
            race,
            jobId,
            baseClass,
            stats: {
                health: stats.maxHealth,
                maxHealth: stats.maxHealth,
                mana: stats.maxMana,
                maxMana: stats.maxMana,
                attack: stats.attack,
                defense: stats.defense,
                speed: stats.speed,
                speedMultiplier: 1,
                magicAttack: stats.magicAttack,
                critChance: stats.critChance,
                castSpeed: 100,
                level,
                experience: typeof experience === 'string' ? parseInt(experience, 10) : (experience || 0),
                experienceToNext: xpToNext
            },
            statPoints,
            baseStats: stats.baseStats,
            unspentStatPoints,
            unspentSkillPoints,
            skillProficiencies,
            skillAdeptness: adeptness,
            position: { x: 0, y: 0, z: 0 },
            rotation: { x: 0, y: 0, z: 0, w: 1 },
            zoneId: 'starter_zone',
            targetId: null,
            lastAttackTime: 0,
            lastManualAttackTime: 0,
            lastRegenTick: Date.now(),
            invulnerableUntil: Date.now() + 3000,
            isDead: false,
            isResting: false,
            restStartedAt: 0,
            currentNpcId: null,
            deathTime: 0,
            nation: null,
            lastSafeZoneId: 'starter_zone',
            skillCooldowns: [],
            activeCast: null,
            statusEffects: [],
            statBreakdown: null,
            effectiveStats: null,
            inventory: [],
            gold: 100,
            equipment: {
                weapon: null,
                armor: null,
                helmet: null,
                boots: null,
                gloves: null,
                legs: null,
                shield: null,
                earring_1: null,
                earring_2: null,
                necklace: null,
                belt: null,
                ring_1: null,
                ring_2: null,
            },
            role: shared_1.AccountRole.PLAYER,
            quests: []
        };
    }
    grantExperience(session, amount) {
        if (session.stats.level >= shared_2.MAX_LEVEL)
            return false;
        session.stats.experience += amount;
        let leveledUp = false;
        while (session.stats.experience >= session.stats.experienceToNext && session.stats.level < shared_2.MAX_LEVEL) {
            session.stats.experience -= session.stats.experienceToNext;
            session.stats.level++;
            session.stats.experienceToNext = (0, shared_2.getExperienceToNextLevel)(session.stats.level);
            const gainedStatPoints = (0, shared_2.getStatPointsGainedAtLevel)(session.stats.level);
            session.unspentStatPoints += gainedStatPoints;
            session.unspentSkillPoints += (0, shared_2.getSkillPointsGainedAtLevel)(session.stats.level);
            this.recalcStats(session);
            leveledUp = true;
            this.levelUpCallbacks.forEach(cb => cb(session.characterId, session.stats.level));
        }
        return leveledUp;
    }
    allocateStatPoint(session, stat) {
        const currentValue = session.statPoints[stat] + (session.baseStats?.[stat] || 0);
        const [cost] = (0, shared_2.getStatPointCost)(currentValue);
        if (session.unspentStatPoints < cost)
            return false;
        if (currentValue >= 99)
            return false;
        session.statPoints[stat] += 1;
        session.unspentStatPoints -= cost;
        this.recalcStats(session);
        return true;
    }
    allocateSkillPoint(session, subCategoryName, count = 1) {
        const validNames = (0, shared_2.getValidSubCategoryNames)();
        if (!validNames.includes(subCategoryName))
            return false;
        if (count <= 0 || !Number.isFinite(count))
            return false;
        if (session.unspentSkillPoints < count)
            return false;
        const designJobId = (0, shared_2.getDesignJobId)(session.jobId);
        const maxPoints = (0, shared_2.getMaxPotential)(designJobId, subCategoryName);
        const currentPoints = session.skillProficiencies[subCategoryName] || 0;
        if (currentPoints + count > maxPoints)
            return false;
        session.skillProficiencies[subCategoryName] = (session.skillProficiencies[subCategoryName] || 0) + count;
        session.unspentSkillPoints -= count;
        if (session.skillAdeptness[subCategoryName] > session.skillProficiencies[subCategoryName]) {
            session.skillAdeptness[subCategoryName] = session.skillProficiencies[subCategoryName];
        }
        (0, shared_2.recalculateCategoryTotals)(session.skillProficiencies);
        return true;
    }
    advanceJob(session, newJobId) {
        const currentJob = shared_2.JOB_DEFINITIONS[session.jobId];
        const newJob = shared_2.JOB_DEFINITIONS[newJobId];
        if (!currentJob || !newJob)
            return false;
        if (newJob.parentJob !== session.jobId)
            return false;
        const requiredLevel = newJob.tier === 2 ? 20 : newJob.tier === 3 ? 45 : 1;
        if (session.stats.level < requiredLevel)
            return false;
        session.jobId = newJobId;
        session.baseClass = newJob.baseClass;
        this.recalcStats(session);
        return true;
    }
    /** Unequip all items back to inventory (for class advancement gear strip). */
    unequipAll(session) {
        let moved = 0;
        let failed = 0;
        for (const slot of Object.keys(session.equipment)) {
            const item = session.equipment[slot];
            if (!item)
                continue;
            const invItem = { itemId: item.itemId, quantity: 1, slot: 0, enhancementLevel: item.enhancementLevel, enhancementElement: item.enhancementElement };
            const added = this.addItemToInventoryWithMeta(session, invItem);
            if (added) {
                session.equipment[slot] = null;
                moved++;
            }
            else {
                failed++;
            }
        }
        if (moved > 0)
            this.recalcStats(session);
        return { moved, failed };
    }
    /** Refund all allocated stat points. */
    resetStatPoints(session) {
        const spent = Object.values(session.statPoints).reduce((sum, v) => sum + v, 0);
        session.statPoints = (0, shared_2.createDefaultStatPoints)();
        session.unspentStatPoints += spent;
        this.recalcStats(session);
    }
    /** Refund all allocated skill proficiency points. */
    resetSkillPoints(session) {
        const categoryKeys = new Set(['melee', 'technique', 'prayer', 'magic', 'special']);
        const spent = Object.entries(session.skillProficiencies)
            .filter(([key]) => !categoryKeys.has(key))
            .reduce((sum, [, v]) => sum + (typeof v === 'number' ? v : 0), 0);
        session.skillProficiencies = (0, shared_2.createDefaultSkillProficiencies)();
        session.unspentSkillPoints += spent;
        this.recalcStats(session);
    }
    getEnhancementBonuses(session) {
        const enh = { attack: 0, defense: 0, health: 0, magicAttackPercent: 0, dodge: 0 };
        for (const slot of Object.values(session.equipment)) {
            if (!slot)
                continue;
            const level = slot.enhancementLevel || 0;
            if (level <= 0)
                continue;
            const def = this.itemSys.getItemDefinition(slot.itemId);
            if (!def)
                continue;
            const eqSlot = def.equipmentSlot;
            if (eqSlot === shared_2.EquipmentSlot.WEAPON) {
                const s = def?.stats;
                const isMagicWeapon = (s?.magicAttack && s.magicAttack > 0) || (s?.INT && s.INT > 0) || (s?.SPI && s.SPI > 0);
                if (!isMagicWeapon) {
                    enh.attack += level * 3;
                }
                if (isMagicWeapon) {
                    enh.magicAttackPercent += level * 0.02;
                }
            }
            else if (eqSlot === shared_2.EquipmentSlot.ARMOR || eqSlot === shared_2.EquipmentSlot.HELMET || eqSlot === shared_2.EquipmentSlot.GLOVES || eqSlot === shared_2.EquipmentSlot.LEGS || eqSlot === shared_2.EquipmentSlot.SHIELD) {
                enh.defense += level * 3;
                enh.health += level * 15;
            }
            else if (eqSlot === shared_2.EquipmentSlot.BOOTS) {
                enh.defense += level * 2;
                enh.dodge += level * 1;
            }
        }
        return enh;
    }
    recalcStats(session) {
        const gear = this.getGearBonuses(session);
        const effectiveStatPoints = {
            STA: session.statPoints.STA + gear.STA,
            STR: session.statPoints.STR + gear.STR,
            AGI: session.statPoints.AGI + gear.AGI,
            DEX: session.statPoints.DEX + gear.DEX,
            SPI: session.statPoints.SPI + gear.SPI,
            INT: session.statPoints.INT + gear.INT,
        };
        const derived = (0, shared_2.calculateDerivedStats)(session.race, session.jobId, session.stats.level, effectiveStatPoints);
        session.baseStats = derived.baseStats;
        const healthRatio = session.stats.maxHealth > 0 ? session.stats.health / session.stats.maxHealth : 1;
        const manaRatio = session.stats.maxMana > 0 ? session.stats.mana / session.stats.maxMana : 1;
        const oldMaxHealth = session.stats.maxHealth;
        const oldMaxMana = session.stats.maxMana;
        session.stats.maxHealth = derived.maxHealth + gear.health;
        session.stats.maxMana = derived.maxMana + gear.mana;
        session.stats.attack = derived.attack + gear.attack;
        session.stats.defense = derived.defense + gear.defense;
        session.stats.speed = derived.speed;
        session.stats.speedMultiplier = 1 + gear.speed;
        session.stats.magicAttack = Math.floor(derived.magicAttack * (1 + gear.magicAttackPercent));
        session.stats.critChance = derived.critChance + gear.criticalChance;
        session.stats.castSpeed = 100 + Math.floor((session.statPoints.DEX + gear.DEX) / 10) * 5 + Math.floor(gear.castSpeed * 100);
        const effective = (0, shared_2.getEffectiveStats)(session.stats, effectiveStatPoints, session.statusEffects || []);
        session.effectiveStats = effective;
        session.stats.attack = effective.attack;
        session.stats.defense = effective.defense;
        session.stats.magicAttack = effective.magicAttack;
        session.stats.maxHealth = effective.maxHealth;
        session.stats.maxMana = effective.maxMana;
        session.stats.speed = effective.speed;
        session.stats.speedMultiplier = (1 + gear.speed) * effective.speedMultiplier;
        if (session.stats.maxHealth !== oldMaxHealth) {
            session.stats.health = Math.floor(effective.maxHealth * healthRatio);
        }
        if (session.stats.maxMana !== oldMaxMana) {
            session.stats.mana = Math.floor(effective.maxMana * manaRatio);
        }
        const { STA, STR, AGI, DEX, SPI, INT, accuracy, dodge, attackSpeed, fireResist, iceResist, lightningResist, poisonResist, darkResist, holyResist, ailmentResist, disorderResist, stunResist, tripResist, freezeResist, burnResist, curseResist, bleedResist, sleepResist, weaknessResist, weakenResist, knockdownResist, knockbackResist, ...flatGear } = gear;
        let buffFireResist = 0, buffIceResist = 0, buffLightningResist = 0, buffPoisonResist = 0, buffDarkResist = 0, buffHolyResist = 0;
        for (const effect of session.statusEffects || []) {
            if (effect.buffData?.resistMods) {
                const mods = effect.buffData.resistMods;
                if (mods.fire)
                    buffFireResist += mods.fire;
                if (mods.ice)
                    buffIceResist += mods.ice;
                if (mods.lightning)
                    buffLightningResist += mods.lightning;
                if (mods.poison)
                    buffPoisonResist += mods.poison;
                if (mods.dark)
                    buffDarkResist += mods.dark;
                if (mods.holy)
                    buffHolyResist += mods.holy;
            }
        }
        session.statBreakdown = (0, shared_2.computeStatBreakdown)(session.statPoints, session.statusEffects || [], { STA, STR, AGI, DEX, SPI, INT }, { accuracy, dodge, attackSpeed, fireResist: fireResist + buffFireResist, iceResist: iceResist + buffIceResist, lightningResist: lightningResist + buffLightningResist, poisonResist: poisonResist + buffPoisonResist, darkResist: darkResist + buffDarkResist, holyResist: holyResist + buffHolyResist, ailmentResist, disorderResist, stunResist, tripResist, freezeResist, burnResist, curseResist, bleedResist, sleepResist, weaknessResist, weakenResist, knockdownResist, knockbackResist });
        const enhBonuses = this.getEnhancementBonuses(session);
        session.statBreakdown.enhancement = enhBonuses;
        const baseStats = session.baseStats || { STA: 0, STR: 0, AGI: 0, DEX: 0, SPI: 0, INT: 0 };
        const totalAgi = (session.statPoints.AGI || 0) + baseStats.AGI + AGI + (session.statBreakdown.buffs?.AGI || 0);
        const totalDex = (session.statPoints.DEX || 0) + baseStats.DEX + DEX + (session.statBreakdown.buffs?.DEX || 0);
        session.statBreakdown.totalDodge = (0, shared_2.calculateDodge)(session.stats.level, totalAgi, effective.dodgeBonus + dodge);
        session.statBreakdown.totalAccuracy = (0, shared_2.calculateAccuracy)(session.stats.level, totalDex, effective.accuracyBonus + accuracy);
        session.statBreakdown.buffCooldownReduction = Math.floor(effective.castTimeReduction * 100);
        const totalSTA = (session.statPoints.STA || 0) + baseStats.STA + STA + (session.statBreakdown.buffs?.STA || 0);
        const totalSPI = (session.statPoints.SPI || 0) + baseStats.SPI + SPI + (session.statBreakdown.buffs?.SPI || 0);
        session.statBreakdown.totalAilmentResist = (0, shared_2.computeAilmentResist)(totalSTA, ailmentResist);
        session.statBreakdown.totalDisorderResist = (0, shared_2.computeDisorderResist)(totalSPI, disorderResist);
        session.statBreakdown.healPercent = gear.healPercent + effective.healPercent;
        this.maintainObeliskBuff(session);
    }
    /**
     * Keeps the visible BUFF_OBELISK status effect in sync with the equipped
     * Obelisk weapon. The mechanical effect (resist-ignore / damage-reduction)
     * is computed off the weapon directly at the damage sites; this buff exists
     * purely so the player sees it in their buff bar.
     *
     * Change-guarded: only mutates `statusEffects` when the buff is added,
     * removed, or its enhancement-level-scaled values change — so calling this
     * from the frequently-run recalcStats does NOT spam updates. Caller is
     * responsible for emitting STATUS_EFFECT_UPDATE after equip/unequip.
     */
    maintainObeliskBuff(session) {
        const values = (0, obeliskBuff_1.getObeliskBuffForWeapon)(this.itemSys, session.equipment?.weapon);
        const effects = session.statusEffects || [];
        const existing = effects.find(e => e.type === shared_2.StatusEffectType.BUFF_OBELISK);
        if (values) {
            const unchanged = existing &&
                existing.buffData?.obeliskResistIgnore === values.resistIgnore &&
                existing.buffData?.obeliskDamageReduction === values.damageReduction;
            if (unchanged)
                return;
            const now = Date.now();
            const buff = {
                id: `buff_obelisk_${session.characterId}`,
                type: shared_2.StatusEffectType.BUFF_OBELISK,
                sourceId: session.characterId,
                targetId: session.characterId,
                potency: 0,
                appliedAt: now,
                duration: 999999999,
                tickInterval: 0,
                lastTickAt: now,
                stacks: 1,
                skillName: 'Obelisk',
                buffData: {
                    obeliskResistIgnore: values.resistIgnore,
                    obeliskDamageReduction: values.damageReduction,
                },
            };
            session.statusEffects = effects.filter(e => e.type !== shared_2.StatusEffectType.BUFF_OBELISK);
            session.statusEffects.push(buff);
        }
        else if (existing) {
            session.statusEffects = effects.filter(e => e.type !== shared_2.StatusEffectType.BUFF_OBELISK);
        }
    }
    healPlayer(session) {
        session.stats.health = session.stats.maxHealth;
        session.stats.mana = session.stats.maxMana;
    }
    addItemToInventory(session, itemId, quantity) {
        if (session.inventory.length >= shared_2.GAME_CONFIG.MAX_INVENTORY_SLOTS)
            return false;
        const existing = session.inventory.find(slot => slot.itemId === itemId);
        const itemDef = this.itemSys.getItemDefinition(itemId);
        if (existing && itemDef && itemDef.maxStack > 1) {
            if (existing.quantity + quantity <= itemDef.maxStack) {
                existing.quantity += quantity;
                return true;
            }
        }
        let emptySlot = -1;
        for (let i = 0; i < shared_2.GAME_CONFIG.MAX_INVENTORY_SLOTS; i++) {
            if (!session.inventory.find(s => s.slot === i)) {
                emptySlot = i;
                break;
            }
        }
        if (emptySlot === -1)
            return false;
        session.inventory.push({ itemId, quantity, slot: emptySlot });
        return true;
    }
    addItemToInventoryWithMeta(session, item) {
        if (session.inventory.length >= shared_2.GAME_CONFIG.MAX_INVENTORY_SLOTS)
            return false;
        const itemDef = this.itemSys.getItemDefinition(item.itemId);
        if (itemDef && itemDef.maxStack > 1 && !item.enhancementLevel) {
            const existing = session.inventory.find(s => s.itemId === item.itemId);
            if (existing && existing.quantity + item.quantity <= itemDef.maxStack) {
                existing.quantity += item.quantity;
                return true;
            }
        }
        let emptySlot = -1;
        for (let i = 0; i < shared_2.GAME_CONFIG.MAX_INVENTORY_SLOTS; i++) {
            if (!session.inventory.find(s => s.slot === i)) {
                emptySlot = i;
                break;
            }
        }
        if (emptySlot === -1)
            return false;
        session.inventory.push({ ...item, slot: emptySlot, quantity: item.quantity });
        return true;
    }
    removeItemFromInventory(session, itemId, quantity) {
        let remaining = quantity;
        for (const slot of session.inventory) {
            if (slot.itemId !== itemId || remaining <= 0)
                continue;
            const take = Math.min(remaining, slot.quantity);
            slot.quantity -= take;
            remaining -= take;
        }
        if (remaining > 0)
            return false;
        session.inventory = session.inventory.filter(s => s.quantity > 0);
        session.inventory.forEach((s, i) => { s.slot = i; });
        return true;
    }
    equipItem(session, itemId) {
        const invSlot = session.inventory.find(s => s.itemId === itemId);
        if (!invSlot)
            return false;
        const itemDef = this.itemSys.getItemDefinition(itemId);
        if (!itemDef || !itemDef.equipmentSlot)
            return false;
        if (session.stats.level < itemDef.requiredLevel)
            return false;
        let slot = itemDef.equipmentSlot;
        if (slot === shared_2.EquipmentSlot.RING_1 || slot === shared_2.EquipmentSlot.RING_2) {
            slot = session.equipment.ring_1 ? shared_2.EquipmentSlot.RING_2 : shared_2.EquipmentSlot.RING_1;
        }
        else if (slot === shared_2.EquipmentSlot.EARRING_1 || slot === shared_2.EquipmentSlot.EARRING_2) {
            slot = session.equipment.earring_1 ? shared_2.EquipmentSlot.EARRING_2 : shared_2.EquipmentSlot.EARRING_1;
        }
        const currentlyEquipped = session.equipment[slot];
        if (currentlyEquipped) {
            this.unequipItem(session, slot);
        }
        session.equipment[slot] = {
            itemId,
            quantity: 1,
            slot: 0,
            enhancementLevel: invSlot.enhancementLevel,
            enhancementElement: invSlot.enhancementElement,
        };
        session.inventory = session.inventory.filter(s => s.itemId !== itemId);
        // Obelisk buff is mutually exclusive with Guardian: an Obelisk weapon
        // wielder cannot be protected by Guardian. Strip this player's BUFF_GUARDED
        // marker on equip. (The protection is also mechanically blocked in
        // findGuardian, so a lingering protector-side redirect does nothing.)
        if (slot === shared_2.EquipmentSlot.WEAPON && itemDef.obeliskBuff && session.statusEffects) {
            session.statusEffects = session.statusEffects.filter(e => e.type !== shared_2.StatusEffectType.BUFF_GUARDED);
        }
        this.recalcStats(session);
        return true;
    }
    unequipItem(session, slot) {
        const equipped = session.equipment[slot];
        if (!equipped)
            return false;
        const item = {
            itemId: equipped.itemId,
            quantity: 1,
            slot: 0,
            enhancementLevel: equipped.enhancementLevel,
            enhancementElement: equipped.enhancementElement,
        };
        const added = this.addItemToInventoryWithMeta(session, item);
        if (!added)
            return false;
        session.equipment[slot] = null;
        this.recalcStats(session);
        return true;
    }
    update(deltaTime) {
    }
}
exports.PlayerSystem = PlayerSystem;
