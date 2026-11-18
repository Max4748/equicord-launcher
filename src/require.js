// index.js généré par electron-hook dans l'asar injecté à la place de app.asar.
//
// electron-hook mappe l'app.asar original de Discord vers ../_app.asar. On n'a
// pas besoin de le charger ici : le patcher d'Equicord (MODLOADER_MOD_ENTRYPOINT)
// s'en charge lui-même, exactement comme avec l'injection native.

// Correctif Linux : quand Discord se relance lui-même (après une mise à jour ou
// un redémarrage complet du client), il faut relancer le launcher plutôt que
// Discord directement, sinon Equicord ne serait pas réinjecté (cf. electron#41463).
// Tout est protégé par try/catch : en cas de pépin, on garde le comportement
// normal et le require du mod s'exécute quand même en fin de fichier.
try {
    if (process.platform === "linux" && process.env.MODLOADER_EXECUTABLE) {
        const { app } = require("electron");
        const originalRelaunch = app.relaunch.bind(app);
        app.relaunch = function (options) {
            try {
                let args;
                try {
                    args = JSON.parse(process.env.MODLOADER_PROCESS_ARGV);
                } catch (_) {
                    args = process.argv.slice(1);
                }
                app.once("quit", () => {
                    require("child_process")
                        .spawn(process.env.MODLOADER_EXECUTABLE, args, {
                            detached: true,
                            stdio: "ignore",
                        })
                        .unref();
                });
            } catch (_) {
                return originalRelaunch(options);
            }
        };
    }
    // Correctif Windows : app.relaunch() passe par le helper « --type=relauncher »
    // d'Electron, qu'electron-hook n'injecte pas (sa commande contient « -- ») ; le
    // Discord relancé n'aurait donc plus Equicord. On relance le launcher tout de
    // suite : il attend la fin de ce processus (EQUICORD_LAUNCHER_WAIT_PID) avant de
    // démarrer Discord, sinon le verrou d'instance unique de Discord ferait échouer
    // le nouveau démarrage.
    if (process.platform === "win32" && process.env.MODLOADER_EXECUTABLE) {
        const { app } = require("electron");
        const originalRelaunch = app.relaunch.bind(app);
        app.relaunch = function (options) {
            try {
                let args;
                try {
                    args = JSON.parse(process.env.MODLOADER_PROCESS_ARGV);
                } catch (_) {
                    args = [];
                }
                // Une commande sans « -- » serait injectée par le hook CreateProcessW
                // d'electron-hook : le launcher recevrait la DLL. « -- » seul = aucun
                // argument Discord pour le launcher.
                if (!args.some((a) => a.includes("--"))) args.push("--");
                require("child_process")
                    .spawn(process.env.MODLOADER_EXECUTABLE, args, {
                        detached: true,
                        stdio: "ignore",
                        env: { ...process.env, EQUICORD_LAUNCHER_WAIT_PID: String(process.pid) },
                    })
                    .unref();
            } catch (_) {
                return originalRelaunch(options);
            }
        };
    }
} catch (_) {
    // on ignore : le mod doit se charger quoi qu'il arrive
}

require(process.env.MODLOADER_MOD_ENTRYPOINT);
