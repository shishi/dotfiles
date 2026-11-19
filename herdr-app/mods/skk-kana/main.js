import { View, div } from "gpui-kit";
import { exec, nextCommand, appHome } from "herdr";

// Herdr hands ctrl+letters to the terminal program before the input method
// sees them unless a composition is open, so SKK's Ctrl+J never reaches macSKK.
// keys.json sends that key here instead, and the mode is selected through the OS.
export default class SkkKana extends View {
  init(_props, cx) {
    cx.spawn(async (cx) => {
      for (;;) {
        const command = await nextCommand();
        if (command === "hiragana") {
          try {
            await exec(`${appHome()}/mods/skk-kana/select-input-source`, ["net.mtgto.inputmethod.macSKK.hiragana"], { timeout: 3000 });
          } catch (error) {
            console.log(`skk-kana: ${error}`);
          }
        }
        cx.notify();
      }
    });
  }

  render() {
    return div().size_full();
  }
}
