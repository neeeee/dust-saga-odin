"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ACCOUNT_ROLE_RANK = exports.AccountRole = void 0;
exports.roleAtLeast = roleAtLeast;
var AccountRole;
(function (AccountRole) {
    AccountRole["PLAYER"] = "player";
    AccountRole["GM"] = "gm";
    AccountRole["ADMIN"] = "admin";
})(AccountRole || (exports.AccountRole = AccountRole = {}));
exports.ACCOUNT_ROLE_RANK = {
    [AccountRole.PLAYER]: 0,
    [AccountRole.GM]: 1,
    [AccountRole.ADMIN]: 2,
};
function roleAtLeast(actual, min) {
    const a = exports.ACCOUNT_ROLE_RANK[actual || AccountRole.PLAYER] ?? 0;
    return a >= (exports.ACCOUNT_ROLE_RANK[min] ?? 0);
}
