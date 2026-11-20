[English](README.md)

> [!WARNING]
> このプラグインは生成AI（Claude）によって作成されました。
> 作者による詳細なレビューは行っておらず、動作確認は一部の環境（Neovim 0.12.5 / macOS）に限られます。
> 利用は自己責任でお願いします。不具合の報告や改善の提案は歓迎します。

# keytree.nvim

現在有効なキーマップを `eza -T` 風のツリーで一覧表示する Neovim プラグインです。

```text
Neovim キーマップ  leader = <Space>  localleader = \  73 件
[config] = 設定（グローバル）   [buffer] = 設定（バッファ）   [default] = Neovim 標準

NORMAL  49
├── <leader>
│   └── f  Find
│       ├── f <leader>ff  Find files  [config]
│       └── g <leader>fg  Live grep  [config]
├── <C-l>  :help CTRL-L-default  [default]
...
```

## 特徴

- 有効なキーマップを、モードごとのツリーで表示します。
- 各キーマップの出所をタグで区別します。
  - `[config]`: 設定で追加・上書きしたグローバルのキーマップ
  - `[buffer]`: バッファローカルのキーマップ（LSP、gitsigns など）
  - `[default]`: Neovim 標準のキーマップ
- 接頭辞に説明を付けられます（例: `<leader>f` → `Find`）。
- 説明（`desc`）のない設定キーマップは除外されるため、ノイズが少なくなります。

## 要件

- Neovim 0.10 以降（`vim.system` を使用）

## インストール

lazy.nvim の例です。

```lua
{
  "Ryosei-Akatsuka/keytree.nvim",
  cmd = "KeymapTree",
  main = "keytree",
  opts = {
    group_labels = {
      ["<leader>f"] = "Find",
    },
  },
}
```

ローカルのディレクトリを直接読み込む場合は、`"Ryosei-Akatsuka/keytree.nvim"` の代わりに `dir = "/path/to/keytree.nvim"` を指定します。

## 設定

`setup(opts)` に渡せる項目と既定値です。

```lua
require("keytree").setup({
  -- 接頭辞に付ける説明。未指定の接頭辞はキーだけを表示する
  group_labels = {},
})
```

## 使い方

| コマンド | 説明 |
| --- | --- |
| `:KeymapTree` | キーマップのツリーを浮動ウィンドウで表示する |

ウィンドウ内では `q` または `<Esc>` で閉じます。

## 補足

- Neovim 標準のキーマップは、初回表示時に `vim.v.progpath --clean --headless` の別プロセスで取得し、設定と区別するためにキャッシュします。そのため初回表示は少し遅くなります。
- `<Plug>` と `<SNR>` のマッピングは表示しません。
- ツリーに表示されるのは、表示時点で読み込まれている通常バッファのバッファローカルなキーマップだけです。

## ライセンス

[MIT](LICENSE)
