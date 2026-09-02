export function heroStateForProgress(progress) {
  const value = Math.min(1, Math.max(0, progress));

  if (value < 0.14) return "intro";
  if (value < 0.25) return "shortcut";
  if (value < 0.33) return "listening";
  if (value < 0.4) return "processing";
  if (value < 0.44) return "saved";
  if (value < 0.48) return "memory";
  if (value < 0.68) return "codex";
  if (value < 0.9) return "writeback";
  return "close";
}
