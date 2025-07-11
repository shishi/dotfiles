;; ~/.config/nvim/after/queries/nix/injections.scm

;; writeShellScript用 - シンプルなケース
(apply_expression
  argument: (indented_string_expression
    (string_fragment) @injection.content)
  (#match? @injection.content "^#!/")
  (#set! injection.language "bash"))

;; writeShellApplication の text フィールド
(binding
  attrpath: (attrpath (identifier) @_name)
  expression: (indented_string_expression
    (string_fragment) @injection.content)
  (#eq? @_name "text")
  (#set! injection.language "bash"))

;; buildPhase, checkPhase などのフェーズ
(binding
  attrpath: (attrpath (identifier) @_phase)
  expression: (indented_string_expression
    (string_fragment) @injection.content)
  (#match? @_phase "^(configurePhase|buildPhase|checkPhase|installPhase|fixupPhase|unpackPhase|patchPhase)$")
  (#set! injection.language "bash"))
