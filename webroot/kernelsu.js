let c = 0;
export function exec(cmd, opt = {}) {
    return new Promise(r => {
        let cb = `exec_callback_${Date.now()}_${c++}`;
        let t = setTimeout(() => {
            delete window[cb];
            r({ errno: 1, stdout: "", stderr: "Timeout" });
        }, opt.timeout || 10000);
        window[cb] = (e, o, er) => {
            clearTimeout(t);
            delete window[cb];
            r({ errno: e, stdout: o, stderr: er });
        };
        if (typeof ksu?.exec === 'function') {
            ksu.exec(cmd, JSON.stringify(opt), cb);
        } else {
            clearTimeout(t);
            r({ errno: 1, stdout: "", stderr: "ksu not available" });
        }
    });
}
export function toast(m) {
    if (typeof ksu?.toast === 'function') ksu.toast(m);
    else alert(m);
}
export function isKSUAvailable() {
    return typeof ksu?.exec === 'function';
}