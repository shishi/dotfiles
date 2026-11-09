// A throwaway shell over the window, in the focused terminal's folder.
// It closes when the shell exits; the dialog is modal so a stray click
// can't hide a still-running shell.

import { View, div } from "gpui-kit";
import { hc, focused, terminals, openOverlay, closeOverlay, notify, props } from "herdr";

// Marks the scratch shell so one left behind can be found again.
const LABEL = "shishi-scratch";
// A start that hasn't answered within this long is taken as abandoned.
const START_MS = 5000;

// Shared by every copy of this mod, for this run of the app only: each
// launcher loads its own module, and overlay ids restart from zero on every
// start, so a saved id could name another window's overlay.
function scratchState() {
  globalThis.shishiScratch ??= { overlay: null, address: null, startedAt: 0 };
  return globalThis.shishiScratch;
}

async function live(address) {
  const r = await hc(["get", address, "--json"]).catch(() => null);
  try {
    return r?.code === 0 && JSON.parse(r.stdout).state === "live";
  } catch {
    return false;
  }
}

export default class Scratch extends View {
  init(_props, cx) {
    // `herdr-app check` renders without an overlay: start nothing then.
    const self = props()?.overlay;
    if (!self) return;
    const state = scratchState();
    // A press while another is still finding or starting the shell would
    // start a second one. Marked here, before the task runs, to cover that gap.
    if (Date.now() - state.startedAt < START_MS) {
      closeOverlay(self);
      return;
    }
    state.startedAt = Date.now();
    cx.spawn(async () => {
      // One scratch shell at a time: the one shown before, else one left
      // behind when a launcher closed before `hc run` answered.
      // terminals() can lag an exit by a moment, so every candidate is checked.
      const candidates = [state.address, ...terminals().filter((t) => t.labels?.[LABEL]).map((t) => t.address)];
      let address = null;
      for (const c of new Set(candidates.filter(Boolean))) {
        if (await live(c)) {
          address = c;
          break;
        }
      }
      if (!address) {
        const f = focused();
        const args = ["run", "--bg", "--json", "--no-parent", "--rm", "--label", `${LABEL}=1`];
        // A remote terminal's folder is on another machine.
        if (f?.cwd && f.terminal && !f.terminal.includes("/")) args.push("--cwd", f.cwd);
        const r = await hc(args).catch((e) => ({ code: 1, stdout: "", stderr: String(e) }));
        try {
          address = r.code === 0 ? JSON.parse(r.stdout).address : null;
        } catch {}
        if (!address) {
          state.startedAt = 0;
          closeOverlay(self);
          notify({ title: "Scratch shell failed", body: r.stderr.trim(), level: "error" });
          return;
        }
      }
      state.address = address;
      state.startedAt = 0;
      // Reopen rather than stack dialogs: when one closes, Herdr hands the
      // keyboard to the dialog left on top's frame, not to its terminal.
      if (state.overlay) closeOverlay(state.overlay);
      // Close this launcher before opening, for the same reason.
      closeOverlay(self);
      state.overlay = openOverlay({ kind: "dialog", modal: true, width: 0.8, height: 0.8, layout: { type: "block", content: { terminal: address } } });
    });
  }

  render(_cx) {
    return div();
  }
}
