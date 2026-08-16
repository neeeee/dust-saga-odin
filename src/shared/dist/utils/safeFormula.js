"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.safeFormulaEval = safeFormulaEval;
function safeFormulaEval(expr, vars) {
    const keys = Object.keys(vars).sort((a, b) => b.length - a.length);
    let safe = expr;
    for (const key of keys) {
        safe = safe.replace(new RegExp(`\\b${key}\\b`, 'g'), `(${vars[key]})`);
    }
    if (!/^[\d\s+\-*/().]+$/.test(safe))
        return 0;
    try {
        return Function(`"use strict"; return (${safe})`)();
    }
    catch {
        return 0;
    }
}
