# zsh-notify

同梱の zsh-notify は、非表示のターミナルでコマンドが失敗した場合、または 30 秒を超えて正常終了した場合に通知します。
この文書は[元のプロジェクト](https://github.com/marzocchi/zsh-notify)の同梱版について説明します。

`notify.plugin.zsh` を読み込んで使います。macOS では Terminal.app または iTerm2 と `terminal-notifier`、Linux では `notify-send` と `xdotool` を使います。Linux では `wmctrl` があるとウィンドウの前面化や注意喚起も行います。

`~/.zshrc` の `zstyle` で通知を設定できます。

```zsh
zstyle ':notify:*' error-title 'Error'
zstyle ':notify:*' success-title 'Success'
zstyle ':notify:*' error-icon '/path/to/error-icon.png'
zstyle ':notify:*' success-icon '/path/to/success-icon.png'
zstyle ':notify:*' error-sound 'Glass'
zstyle ':notify:*' success-sound 'default'
zstyle ':notify:*' activate-terminal yes
zstyle ':notify:*' command-complete-timeout 15
```

タイトル、アイコン、音声、前面化の設定は組み込み notifier で使います。Linux の音声設定には音声ファイルのパスを指定します。失敗時の通知には時間のしきい値を適用しません。

カスタム notifier を使う場合は、次の設定を追加します。通知種別 `error` または `success` を第 1 引数に、コマンドの文字列を標準入力に渡します。

```zsh
zstyle ':notify:*' notifier ~/bin/my-notifier
```
