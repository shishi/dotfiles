# Snapshot file
# Unset all aliases to avoid conflicts with functions
unalias -a 2>/dev/null || true
# Functions
eval "$(echo 'Z2F3a2xpYnBhdGhfYXBwZW5kICgpIAp7IAogICAgWyAteiAiJEFXS0xJQlBBVEgiIF0gJiYgQVdL
TElCUEFUSD1gZ2F3ayAnQkVHSU4ge3ByaW50IEVOVklST05bIkFXS0xJQlBBVEgiXX0nYDsKICAg
IGV4cG9ydCBBV0tMSUJQQVRIPSIkQVdLTElCUEFUSDokKiIKfQo=' | base64 -d)" > /dev/null 2>&1
eval "$(echo 'Z2F3a2xpYnBhdGhfZGVmYXVsdCAoKSAKeyAKICAgIHVuc2V0IEFXS0xJQlBBVEg7CiAgICBleHBv
cnQgQVdLTElCUEFUSD1gZ2F3ayAnQkVHSU4ge3ByaW50IEVOVklST05bIkFXS0xJQlBBVEgiXX0n
YAp9Cg==' | base64 -d)" > /dev/null 2>&1
eval "$(echo 'Z2F3a2xpYnBhdGhfcHJlcGVuZCAoKSAKeyAKICAgIFsgLXogIiRBV0tMSUJQQVRIIiBdICYmIEFX
S0xJQlBBVEg9YGdhd2sgJ0JFR0lOIHtwcmludCBFTlZJUk9OWyJBV0tMSUJQQVRIIl19J2A7CiAg
ICBleHBvcnQgQVdLTElCUEFUSD0iJCo6JEFXS0xJQlBBVEgiCn0K' | base64 -d)" > /dev/null 2>&1
eval "$(echo 'Z2F3a3BhdGhfYXBwZW5kICgpIAp7IAogICAgWyAteiAiJEFXS1BBVEgiIF0gJiYgQVdLUEFUSD1g
Z2F3ayAnQkVHSU4ge3ByaW50IEVOVklST05bIkFXS1BBVEgiXX0nYDsKICAgIGV4cG9ydCBBV0tQ
QVRIPSIkQVdLUEFUSDokKiIKfQo=' | base64 -d)" > /dev/null 2>&1
eval "$(echo 'Z2F3a3BhdGhfZGVmYXVsdCAoKSAKeyAKICAgIHVuc2V0IEFXS1BBVEg7CiAgICBleHBvcnQgQVdL
UEFUSD1gZ2F3ayAnQkVHSU4ge3ByaW50IEVOVklST05bIkFXS1BBVEgiXX0nYAp9Cg==' | base64 -d)" > /dev/null 2>&1
eval "$(echo 'Z2F3a3BhdGhfcHJlcGVuZCAoKSAKeyAKICAgIFsgLXogIiRBV0tQQVRIIiBdICYmIEFXS1BBVEg9
YGdhd2sgJ0JFR0lOIHtwcmludCBFTlZJUk9OWyJBV0tQQVRIIl19J2A7CiAgICBleHBvcnQgQVdL
UEFUSD0iJCo6JEFXS1BBVEgiCn0K' | base64 -d)" > /dev/null 2>&1
# Shell Options
shopt -u autocd
shopt -u assoc_expand_once
shopt -u cdable_vars
shopt -u cdspell
shopt -u checkhash
shopt -u checkjobs
shopt -s checkwinsize
shopt -s cmdhist
shopt -u compat31
shopt -u compat32
shopt -u compat40
shopt -u compat41
shopt -u compat42
shopt -u compat43
shopt -u compat44
shopt -s complete_fullquote
shopt -u direxpand
shopt -u dirspell
shopt -u dotglob
shopt -u execfail
shopt -u expand_aliases
shopt -u extdebug
shopt -u extglob
shopt -s extquote
shopt -u failglob
shopt -s force_fignore
shopt -s globasciiranges
shopt -s globskipdots
shopt -u globstar
shopt -u gnu_errfmt
shopt -u histappend
shopt -u histreedit
shopt -u histverify
shopt -s hostcomplete
shopt -u huponexit
shopt -u inherit_errexit
shopt -s interactive_comments
shopt -u lastpipe
shopt -u lithist
shopt -u localvar_inherit
shopt -u localvar_unset
shopt -s login_shell
shopt -u mailwarn
shopt -u no_empty_cmd_completion
shopt -u nocaseglob
shopt -u nocasematch
shopt -u noexpand_translation
shopt -u nullglob
shopt -s patsub_replacement
shopt -s progcomp
shopt -u progcomp_alias
shopt -s promptvars
shopt -u restricted_shell
shopt -u shift_verbose
shopt -s sourcepath
shopt -u varredir_close
shopt -u xpg_echo
set -o braceexpand
set -o hashall
set -o interactive-comments
set -o monitor
set -o onecmd
shopt -s expand_aliases
# Aliases
# Check for rg availability
if ! (unalias rg 2>/dev/null; command -v rg) >/dev/null 2>&1; then
  alias rg='/home/shishi/.local/share/claude/versions/2.1.19 --ripgrep'
fi
export PATH=/nix/store/c2p7haf4zzkbrir9zs662r68c5dmylbq-patchelf-0.15.2/bin\:/nix/store/a245z3cvf9x9sn0xlk6k8j9xhxbhda1z-gcc-wrapper-15.2.0/bin\:/nix/store/mjf8jlq9grydcdvyw6hb063x5c34g5gf-gcc-15.2.0/bin\:/nix/store/0bdqq2z98kg2hfn3k60if6pb5fd5p10h-glibc-2.42-47-bin/bin\:/nix/store/i2vmgx46q9hd3z6rigaiman3wl3i2gc4-coreutils-9.9/bin\:/nix/store/i6ppbrlpp6yki8qvka7nyv091xa8dchx-binutils-wrapper-2.44/bin\:/nix/store/47mn80zqpygykqailwzw8zlag4cgl75q-binutils-2.44/bin\:/nix/store/6jz2pgmsh06z9a83qi33f6lp9w2q6mzm-ruby-3.3.10/bin\:/nix/store/idirrw254q6758fivj9myvad0kqpbfzi-bundler-2.7.2/bin\:/nix/store/azkh9xkfaphcs7cj5l43rh4a92zjc510-nodejs-22.22.0-dev/bin\:/nix/store/cv3yxgf7zp70wk8d8lg5zi84lg35nyxs-nodejs-22.22.0/bin\:/nix/store/jfix66kzid1391z3vfcn156lcp070rgg-chromium-144.0.7559.96/bin\:/nix/store/50fnfi2484nn8dzbh7ric41a96ml3581-glib-2.86.3-dev/bin\:/nix/store/ykz6g9bnl3kka132wiw355rzk0bibdqn-gettext-0.25.1/bin\:/nix/store/flz261l810xa8w6narg9p9nggx4lrv3x-glib-2.86.3-bin/bin\:/nix/store/33avy155kh13axsprx8dv3jn1hgrlxj0-nss-3.112.2-dev/bin\:/nix/store/lp1p640jmxrx2gwsmk44xiz8d8r57inl-nspr-4.38.2-dev/bin\:/nix/store/6vwhdd1hzqdx5v1z1p5g5n8z5ljvna6f-expat-2.7.3-dev/bin\:/nix/store/jh07azrfyi3x24x4cwm3q8abxnj6m9wd-dbus-1.14.10-lib/bin\:/nix/store/pb9dhpk6qxjybb8p7prvs18ls2vxk51a-dbus-1.14.10/bin\:/nix/store/42bjj6vp4q6wj4gbs0v6kzjxl82v1rqk-cups-2.4.16-dev/bin\:/nix/store/47bvlqrx8yqw4fi9j4j4f599s9zc6q2w-cups-2.4.16/bin\:/nix/store/hn6qyh7khbs3ms7fsqzq3d4zk6h69p0w-libdrm-2.4.131-bin/bin\:/nix/store/ni6pwnn5cg4mwm2fkmqrm2bzjvj16b64-libxkbcommon-1.11.0/bin\:/nix/store/bvk4cw5w1h1nw6fy1z7zn2hqkvcc6d2i-cairo-1.18.4-dev/bin\:/nix/store/d4i1vzn8wsna9rjcc2h55qcsnd8mg815-freetype-2.13.3-dev/bin\:/nix/store/90yw24gqmwph4xjp4mqhpx1y1gcrvqla-bzip2-1.0.8-bin/bin\:/nix/store/494flzsx9j86bshnds5sy6f4iy4g7gxi-brotli-1.2.0/bin\:/nix/store/d3z2mb1hqk0pmzal1i07bra1gwnj4k52-libpng-apng-1.6.53-dev/bin\:/nix/store/y20r6hlgfv26dpm016k6rmf6c8rnmzfl-fontconfig-2.17.1-bin/bin\:/nix/store/x5ydpx2a4pcgzl5y0qklvr3znkdc3ab2-harfbuzz-12.3.0-dev/bin\:/nix/store/v6d9ag8hs0sfl3q0ikxdpp8k26csl0am-graphite2-1.3.14/bin\:/nix/store/pxyjx7ilqh2gnpdhj6856phzjycjsxr3-pango-1.57.0-bin/bin\:/nix/store/ij05c25c11dissklsp3fiysb8kah7iq5-alsa-lib-1.2.15.1/bin\:/nix/store/hs8lghrr7is152zn3kpyhgggc8q6a8b2-mesa-25.3.3/bin\:/nix/store/k490s4vkdj7azhkdpamdljhj8rb4p8lw-gtk+3-3.24.51-dev/bin\:/nix/store/dkw48k243m15sjwlawz1lc6vmmbqwh4b-fribidi-1.0.16/bin\:/nix/store/4ndhnsp212zd65c80yvs9dvyhdkxndj7-gdk-pixbuf-2.44.4-dev/bin\:/nix/store/fb0ba2fzpmiyjhaqgqsg58mx969lsd9k-libtiff-4.7.1-bin/bin\:/nix/store/w30wm0xg90zi78k8j3kqyaxp1qcp1g9d-libjpeg-turbo-3.1.3-bin/bin\:/nix/store/izs6bs8fflbyg7djv7p1c753jyinxvx3-gdk-pixbuf-2.44.4/bin\:/nix/store/cg89xd93ldyjwxjw05zzpgs1yr3nzj9c-gtk+3-3.24.51/bin\:/nix/store/i5scwnmmp6ca1xwxgsv1zj0j5d7ph1ra-xvfb-run-1+g87f6705/bin\:/nix/store/zys6d102zp171wpwcs08g632886w2qxs-xz-5.8.2-bin/bin\:/nix/store/4ip8dc15r758m8yc30bycq0vxj8ic6yg-xorg-server-21.1.21/bin\:/nix/store/i2vmgx46q9hd3z6rigaiman3wl3i2gc4-coreutils-9.9/bin\:/nix/store/16wfacfgap3chf7mcjnd8dwi85dj4qqi-findutils-4.10.0/bin\:/nix/store/3p87h6dn5i87i3iq9364imzbqgwvkg2p-diffutils-3.12/bin\:/nix/store/ryz8kcrm2bxpccllfqlb7qldsfnqp5c2-gnused-4.9/bin\:/nix/store/02vv0r262agf9j5n2y1gmbjvdf12zkl0-gnugrep-3.12/bin\:/nix/store/2xq9rayckw8zq26k274xxlikn77jn60j-gawk-5.3.2/bin\:/nix/store/qyg62bc2xnpwz0fa9prqxvvk00zj4g9q-gnutar-1.35/bin\:/nix/store/84yyzmxs7mb8nhkvcfv9n1l9irpb6mnq-gzip-1.14/bin\:/nix/store/90yw24gqmwph4xjp4mqhpx1y1gcrvqla-bzip2-1.0.8-bin/bin\:/nix/store/vbah5c4rzy1q1hbqhginyxjhj8d4dj8j-gnumake-4.4.1/bin\:/nix/store/f15k3dpilmiyv6zgpib289rnjykgr1r4-bash-5.3p9/bin\:/nix/store/wwij6563c6wbg4kzgjhng7vlhf7api19-patch-2.8/bin\:/nix/store/zys6d102zp171wpwcs08g632886w2qxs-xz-5.8.2-bin/bin\:/nix/store/nyy0bvgjwd98x7ih8pl6pr79qjljgsf7-file-5.45/bin\:/home/shishi/.local/share/gem/ruby/3.4.0/bin\:/home/shishi/.console-ninja/.bin\:/home/shishi/.cargo/bin\:/home/shishi/.local/bin\:/home/shishi/dev/bin\:/usr/local/sbin\:/usr/local/bin\:/home/shishi/.nix-profile/bin\:/nix/var/nix/profiles/default/bin\:/home/shishi/.cargo/bin\:/usr/local/sbin\:/usr/local/bin\:/usr/sbin\:/usr/bin\:/sbin\:/bin\:/usr/games\:/usr/local/games\:/usr/lib/wsl/lib\:/snap/bin
