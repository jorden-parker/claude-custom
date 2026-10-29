const tty = require("node:tty");

tty.ReadStream.prototype.setRawMode = function (flag) {
  const raw = Boolean(flag);
  this._handle?.setRawMode(raw);
  this.isRaw = raw;
  return this;
};
