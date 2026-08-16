"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.STAT_TYPES = exports.StatType = exports.RacialPassiveId = exports.Race = void 0;
exports.createDefaultStatPoints = createDefaultStatPoints;
var Race;
(function (Race) {
    Race["HUMAN"] = "human";
    Race["ELF"] = "elf";
    Race["DWARF"] = "dwarf";
    Race["MYRINE"] = "myrine";
    Race["ENKIDU"] = "enkidu";
    Race["LAPIN"] = "lapin";
})(Race || (exports.Race = Race = {}));
var RacialPassiveId;
(function (RacialPassiveId) {
    RacialPassiveId["HUMAN_FIGHTING_SPIRIT"] = "human_fighting_spirit";
    RacialPassiveId["HUMAN_ADAPTABILITY"] = "human_adaptability";
    RacialPassiveId["HUMAN_BREWER"] = "human_brewer";
    RacialPassiveId["ELF_HAWKEYE"] = "elf_hawkeye";
    RacialPassiveId["ELF_NATURES_HARMONY"] = "elf_natures_harmony";
    RacialPassiveId["ELF_STEADFASTNESS"] = "elf_steadfastness";
    RacialPassiveId["DWARF_STRONGHEARTED"] = "dwarf_stronghearted";
    RacialPassiveId["DWARF_SPIRIT"] = "dwarf_spirit";
    RacialPassiveId["DWARF_FILIAL_PIETY"] = "dwarf_filial_piety";
    RacialPassiveId["MYRINE_ACUTE_SENSES"] = "myrine_acute_senses";
    RacialPassiveId["MYRINE_SHARPNESS"] = "myrine_sharpness";
    RacialPassiveId["MYRINE_CALMNESS"] = "myrine_calmness";
    RacialPassiveId["ENKIDU_STONE_SKIN"] = "enkidu_stone_skin";
    RacialPassiveId["ENKIDU_STRONG_ARM"] = "enkidu_strong_arm";
    RacialPassiveId["ENKIDU_LAPIN_SUPPORT"] = "enkidu_lapin_support";
    RacialPassiveId["LAPIN_MAGIC_RESISTANCE"] = "lapin_magic_resistance";
    RacialPassiveId["LAPIN_INNER_LIGHT"] = "lapin_inner_light";
    RacialPassiveId["LAPIN_ENKIDU_SUPPORT"] = "lapin_enkidu_support";
})(RacialPassiveId || (exports.RacialPassiveId = RacialPassiveId = {}));
var StatType;
(function (StatType) {
    StatType["STA"] = "STA";
    StatType["STR"] = "STR";
    StatType["AGI"] = "AGI";
    StatType["DEX"] = "DEX";
    StatType["SPI"] = "SPI";
    StatType["INT"] = "INT";
})(StatType || (exports.StatType = StatType = {}));
exports.STAT_TYPES = [
    StatType.STA,
    StatType.STR,
    StatType.AGI,
    StatType.DEX,
    StatType.SPI,
    StatType.INT
];
function createDefaultStatPoints() {
    return { STA: 0, STR: 0, AGI: 0, DEX: 0, SPI: 0, INT: 0 };
}
