// Slår ihop (eller tar bort) Tamanotchis hooks i Claude Codes settings.json.
// Körs med: osascript -l JavaScript merge-hooks.js install|uninstall <settings.json> <hook-sökväg>
ObjC.import('Foundation');

function readText(path) {
  const s = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
  return s.isNil() ? null : ObjC.unwrap(s);
}
function writeText(path, text) {
  $(text).writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null);
}

function run(argv) {
  const [mode, settingsPath, hookPath, prevPath] = argv;
  const raw = readText(settingsPath);
  const settings = raw && raw.trim() ? JSON.parse(raw) : {};
  settings.hooks = settings.hooks || {};

  // Matchar både nya "tamanotchi-hook" och gamla "notchi-hook", så gamla hooks ersätts
  const MARK = 'notchi-hook';
  // Händelser som bara informerar körs i bakgrunden (async) så att Claude Code aldrig väntar.
  const events = {
    SessionStart:      { async: true },
    UserPromptSubmit:  { async: true },
    PreToolUse:        { async: true },
    PostToolUse:       { async: true },
    Notification:      { async: true },
    Stop:              { async: true },
    SessionEnd:        { async: true },
    // Godkännanden måste vänta på ditt svar
    PermissionRequest: { async: false, timeout: 600 },
  };

  for (const ev of Object.keys(events)) {
    const groups = (settings.hooks[ev] || []).filter(g => !JSON.stringify(g).includes(MARK));
    if (mode === 'install') {
      const handler = { type: 'command', command: hookPath, args: [] };
      if (events[ev].async) handler.async = true;
      if (events[ev].timeout) handler.timeout = events[ev].timeout;
      groups.push({ matcher: '*', hooks: [handler] });
    }
    if (groups.length) settings.hooks[ev] = groups; else delete settings.hooks[ev];
  }
  if (Object.keys(settings.hooks).length === 0) delete settings.hooks;

  // Statusraden: där skickar Claude Code din användning (5 tim / vecka).
  // En statusrad du redan hade sparas och körs vidare av Tamanotchi, så den syns precis som förut.
  const sl = settings.statusLine;
  const isOurs = sl && typeof sl.command === 'string' && sl.command.includes(MARK);
  if (mode === 'install') {
    if (sl && !isOurs && prevPath) {
      writeText(prevPath, sl.type === 'command' && sl.command ? sl.command : '');
    }
    settings.statusLine = { type: 'command', command: hookPath + ' --statusline', padding: 0 };
  } else if (isOurs) {
    const prev = prevPath ? readText(prevPath) : null;
    if (prev && prev.trim()) settings.statusLine = { type: 'command', command: prev.trim() };
    else delete settings.statusLine;
  }

  writeText(settingsPath, JSON.stringify(settings, null, 2) + '\n');
  return mode === 'install' ? 'Hooks installerade.' : 'Hooks borttagna.';
}
