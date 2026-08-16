"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.QUEST_COOLDOWN_MS = exports.QuestRepeatInterval = exports.QuestStatus = exports.QuestType = void 0;
var QuestType;
(function (QuestType) {
    QuestType["KILL"] = "kill";
    QuestType["COLLECT"] = "collect";
    QuestType["TALK"] = "talk";
    QuestType["EXPLORE"] = "explore";
    QuestType["ESCORT"] = "escort";
})(QuestType || (exports.QuestType = QuestType = {}));
var QuestStatus;
(function (QuestStatus) {
    QuestStatus["AVAILABLE"] = "available";
    QuestStatus["IN_PROGRESS"] = "in_progress";
    QuestStatus["COMPLETED"] = "completed";
    QuestStatus["TURNED_IN"] = "turned_in";
})(QuestStatus || (exports.QuestStatus = QuestStatus = {}));
var QuestRepeatInterval;
(function (QuestRepeatInterval) {
    QuestRepeatInterval["UNLIMITED"] = "unlimited";
    QuestRepeatInterval["DAILY"] = "daily";
    QuestRepeatInterval["WEEKLY"] = "weekly";
})(QuestRepeatInterval || (exports.QuestRepeatInterval = QuestRepeatInterval = {}));
exports.QUEST_COOLDOWN_MS = {
    [QuestRepeatInterval.UNLIMITED]: 0,
    [QuestRepeatInterval.DAILY]: 24 * 60 * 60 * 1000,
    [QuestRepeatInterval.WEEKLY]: 7 * 24 * 60 * 60 * 1000,
};
