const fs = require("node:fs");

const originalWatch = fs.watch;

fs.watch = function (target, options, listener) {
  const watcher = originalWatch.call(this, target, options, listener);
  watcher.on("error", (error) => {
    if (error.code === "EMFILE") return;
    if (watcher.listenerCount("error") === 1) throw error;
  });
  return watcher;
};
