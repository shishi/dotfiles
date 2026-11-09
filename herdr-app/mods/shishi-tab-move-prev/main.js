// Moves the shown tab one place, skipping settled tabs. Opened by
// mod.open from keys.json; does its work and closes at once.

import { View, div } from "gpui-kit";
import { spaces, run, props, closeOverlay } from "herdr";

const STEP = -1;

export default class TabMove extends View {
  init(_props, _cx) {
    const space = spaces().find((s) => s.active);
    const shown = space?.tabs.filter((t) => !t.settled) ?? [];
    const from = shown.findIndex((t) => t.active);
    const neighbor = from < 0 ? undefined : shown[from + STEP];
    if (neighbor) run("tab.move", { id: shown[from].id, index: neighbor.index });
    const self = props()?.overlay;
    if (self) closeOverlay(self);
  }

  render(_cx) {
    return div();
  }
}
