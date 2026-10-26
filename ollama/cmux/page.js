var __CC_ALLOWED = ["localhost", "127.0.0.1", "[::1]"];
var __CC_PROXY = {
  server: "http://127.0.0.1:9",
  bypass: "localhost,127.0.0.1,[::1]",
};
var __CC_CONSOLE_TYPES = ["error", "warning", "warn"];
var __CC_MAX_CONSOLE = 100;
var __CC_DEFAULT_SCROLL = 600;
var __CC_LOCATOR_ACTIONS = {
  click: (locator) => locator.click(),
  dblclick: (locator) => locator.dblclick(),
  hover: (locator) => locator.hover(),
  focus: (locator) => locator.focus(),
  check: (locator) => locator.check(),
  uncheck: (locator) => locator.uncheck(),
  fill: (locator, text) => locator.fill(text),
  type: (locator, text) => locator.type(text),
  select: (locator, text) => locator.selectOption(text),
};

function __ccSleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function __cc_configure_proxy() {
  const configured = await session.configure({ proxy: __CC_PROXY });
  if (!configured || !configured.proxy) {
    throw new Error("could not keep the browser off your own profile");
  }
}

async function __cc_lock() {
  await __cc_configure_proxy();
  if (
    JSON.stringify(session.allowedDomains()) !== JSON.stringify(__CC_ALLOWED)
  ) {
    session.allowedDomains(__CC_ALLOWED, { lock: true });
  }
  if (
    JSON.stringify(session.allowedDomains()) !== JSON.stringify(__CC_ALLOWED)
  ) {
    throw new Error("could not lock the browser to localhost");
  }
}

function __ccAllowedHost(url) {
  try {
    return __CC_ALLOWED.includes(new URL(url).hostname);
  } catch (error) {
    return false;
  }
}

async function __cc_check_host() {
  const url = page.url();
  if (url !== "about:blank" && !__ccAllowedHost(url)) {
    throw new Error("page left localhost: " + url);
  }
}

async function __ccNeedTab() {
  if (!globalThis.__ccTab) {
    throw new Error("call page_check first");
  }
  await tabs.use(globalThis.__ccTab);
}

function __ccClearBuffers() {
  globalThis.__ccErrors = [];
  globalThis.__ccConsole = [];
}

function __ccAttachListeners() {
  if (globalThis.__ccListened === globalThis.__ccTab) {
    return;
  }
  globalThis.__ccListened = globalThis.__ccTab;
  page.on("console", (message) => {
    if (
      __CC_CONSOLE_TYPES.includes(message.type()) &&
      globalThis.__ccConsole.length < __CC_MAX_CONSOLE
    ) {
      globalThis.__ccConsole.push("[" + message.type() + "] " + message.text());
    }
  });
  page.on("pageerror", (error) => {
    globalThis.__ccErrors.push(
      String(error && error.message ? error.message : error),
    );
  });
}

async function __ccSettle() {
  await page.waitForLoadState("load").catch(() => {});
  await __ccSleep(1000);
  await __cc_check_host();
}

async function __ccReport(surfaceId) {
  return {
    url: page.url(),
    errors: globalThis.__ccErrors.slice(),
    console: globalThis.__ccConsole.slice(),
    surface: surfaceId,
  };
}

async function __cc_open(request) {
  await __cc_lock();
  __ccClearBuffers();
  if (!globalThis.__ccTab) {
    globalThis.__ccTab = await tabs.open(request.url, { background: true });
    await tabs.use(globalThis.__ccTab);
  } else {
    await tabs.use(globalThis.__ccTab);
    await page.goto(request.url);
  }
  __ccAttachListeners();
  await __ccSettle();
  return __ccReport(
    globalThis.__ccTab && globalThis.__ccTab.id ? globalThis.__ccTab.id : null,
  );
}

async function __cc_snapshot() {
  await __cc_lock();
  await __ccNeedTab();
  const elements = String(await snapshot());
  await __cc_check_host();
  return { elements: elements };
}

async function __cc_act(request) {
  await __cc_lock();
  await __ccNeedTab();
  __ccClearBuffers();
  if (request.action === "press") {
    await page.keyboard.press(request.text);
  } else if (request.action === "scroll") {
    await page.mouse.wheel(0, Number(request.text || __CC_DEFAULT_SCROLL));
  } else {
    await __CC_LOCATOR_ACTIONS[request.action](
      page.locator(request.target),
      request.text,
    );
  }
  await __ccSettle();
  const report = await __ccReport(null);
  report.elements = String(await snapshot());
  return report;
}

async function __cc_lock_only() {
  await __cc_lock();
  return { allowed: session.allowedDomains() };
}

async function __ccTryOpen(url) {
  try {
    const tab = await tabs.open(url, { background: true });
    if (tab && tab.close) {
      await tab.close();
    }
    return "reached";
  } catch (error) {
    return "blocked";
  }
}

async function __ccTryGoto(url) {
  try {
    await page.goto(url);
    return "reached";
  } catch (error) {
    return "blocked";
  }
}

async function __ccLocalText(url) {
  const tab = await tabs.open(url, { background: true });
  await tabs.use(tab);
  await page.waitForLoadState("load").catch(() => {});
  return page.evaluate(() => document.body.innerText);
}

async function __cc_selftest(request) {
  await __cc_lock();
  const home = await tabs.open("about:blank", { background: true });
  await tabs.use(home);
  const fetched = await page.evaluate(() =>
    fetch("https://example.com/").then(
      () => "reached",
      () => "blocked",
    ),
  );
  const opened = await __ccTryOpen("https://example.com/");
  const navigated = await __ccTryGoto("https://example.com/");
  const local = await __ccLocalText(request.localUrl);
  return {
    fetch: fetched,
    open: opened,
    goto: navigated,
    allowed: session.allowedDomains(),
    local: local,
  };
}

var __CC_OPS = {
  lock: __cc_lock_only,
  open: __cc_open,
  snapshot: __cc_snapshot,
  act: __cc_act,
  selftest: __cc_selftest,
};

async function __cc_run(request) {
  if (!Object.prototype.hasOwnProperty.call(__CC_OPS, request.op)) {
    throw new Error("unknown op " + request.op);
  }
  return JSON.stringify(await __CC_OPS[request.op](request));
}
