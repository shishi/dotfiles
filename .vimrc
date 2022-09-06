"*****************************************************************************
"" Basic Setup
"*****************************************************************************"
"" Encoding
set encoding=utf-8
set fileencoding=utf-8
set fileencodings=iso-2022-jp,euc-jp,sjis,utf-8
set fileformats=unix,dos,mac
"set bomb
set ttyfast

"" Fix backspace indent
set backspace=indent,eol,start

"" Tabs. May be overriten by autocmd rules
set autoindent
set smartindent
set tabstop=4
set softtabstop=0
set shiftwidth=4
set expandtab

"" Map leader to ,
let mapleader=','

"" Enable hidden buffers
set hidden

"" Searching
set hlsearch
set incsearch
set ignorecase
set smartcase
set wrapscan
set gdefault

"" Directories for swp files
"set nobackup
"set noswapfile
"set noundofile
set directory=/tmp
set backupdir=/tmp
set undodir=/tmp

"" integration
set clipboard=unnamed,unnamedplus
set mouse=a
set ttymouse=xterm2
set shell=/bin/bash
set shellslash
set iminsert=0

"" command line
set showcmd
set wildmenu wildmode=list:longest,full
set history=5000

"" beep
set visualbell t_vb=
set noerrorbells

"*****************************************************************************
"" Visual Settigns
"*****************************************************************************
syntax on
set ruler
set number

colorscheme desert

set mousemodel=popup
set nocursorline
set guioptions=egmrti
"set guifont=Monospace\ 8

if has("gui_running")
  if has("gui_mac") || has("gui_macvim")
    set guifont=Menlo:h12
    set transparency=7
  endif
else
  let g:CSApprox_loaded = 1

  if $COLORTERM == 'gnome-terminal'
    set term=gnome-256color
  else
    if $TERM == 'xterm'
      set term=xterm-256color
    endif
  endif
endif

if &term =~ '256color'
  set t_ut=
endif

"" Disable the blinking cursor.
set gcr=a:blinkon0
set scrolloff=3

"" Status bar
set laststatus=2

"" Use modeline overrides
set modeline
set modelines=10

set title
set titleold="Terminal"
set titlestring=%F

"*****************************************************************************
"" Functions
"*****************************************************************************
if !exists('*s:setupWrapping')
  function s:setupWrapping()
    set wrap
    set wm=2
    set textwidth=79
  endfunction
endif

if !exists('*TrimWhiteSpace')
  function TrimWhiteSpace()
    let @*=line(".")
    %s/\s*$//e
    ''
  endfunction
endif

"*****************************************************************************
"" Autocmd Rules
"*****************************************************************************
"" The PC is fast enough, do syntax highlight syncing from start
autocmd BufEnter * :syntax sync fromstart

"" Remember cursor position
autocmd BufReadPost * if line("'\"") > 1 && line("'\"") <= line("$") | exe "normal! g`\"" | endif

"" txt
autocmd BufRead,BufNewFile *.txt call s:setupWrapping()

"" make/cmake
autocmd FileType make setlocal noexpandtab
autocmd BufNewFile,BufRead CMakeLists.txt setlocal filetype=cmake

if has("gui_running")
  autocmd BufWritePre * :call TrimWhiteSpace()
endif

"" remove trailing space
autocmd BufWritePre * :%s/\s\+$//e

set autoread

"*****************************************************************************
"" Abbreviations
"*****************************************************************************
"" no one is really happy until you have this shortcuts
cnoreabbrev W! w!
cnoreabbrev Q! q!
cnoreabbrev Wq wq
cnoreabbrev Wa wa
cnoreabbrev wQ wq
cnoreabbrev WQ wq
cnoreabbrev W w
cnoreabbrev Q q

"*****************************************************************************
"" Mappings
"*****************************************************************************
" "" move for insert mode
" inoremap <M-j> <Down>
" inoremap <M-k> <Up>
" inoremap <M-h> <Left>
" inoremap <M-l> <Right>

"" move window
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-h> <C-w>h
nnoremap <C-l> <C-w>l
nnoremap <C-w> <C-w>w

"" auto complete bracket
inoremap { {}<LEFT>
inoremap [ []<LEFT>
inoremap ( ()<LEFT>
inoremap " ""<LEFT>
inoremap ' ''<LEFT>

"" Split
noremap <Leader>h :<C-u>split<CR>
noremap <Leader>v :<C-u>vsplit<CR>

"" Set working directory
nnoremap <leader>. :lcd %:p:h<CR>

"" Opens an edit command with the path of the currently edited file filled in
noremap <Leader>e :e <C-R>=expand("%:p:h") . "/" <CR>

"" Opens a tab edit command with the path of the currently edited file filled
noremap <Leader>te :tabe <C-R>=expand("%:p:h") . "/" <CR>

"" Buffer nav
noremap <leader>z :bp<CR>
noremap <leader>q :bp<CR>
noremap <leader>x :bn<CR>
noremap <leader>w :bn<CR>

"" Close buffer
noremap <leader>b :bd<CR>

"" Clean search (highlight)
nnoremap <silent> <leader><space> :noh<cr>

"" Vmap for maintain Visual Mode after shifting > and <
vmap < <gv
vmap > >gv

"" Remove trailing whitespace on <leader>S
nnoremap <silent> <leader>S :call TrimWhiteSpace()<cr>:let @/=''<CR>

"" Copy/Paste/Cut
noremap YY "+y<CR>
noremap P "+gP<CR>
noremap XX "+x<CR>

"" Open Configs
nnoremap <Leader>erc :<C-u>tabnew ~/.vimrc<CR>
nnoremap <Leader>rrc :<C-u>source ~/.vimrc<CR>
nnoremap <Leader>rgrc :<C-u>source ~/.gvimrc<CR>

"*****************************************************************************
"" Tweaks
"*****************************************************************************

if has('macunix')
  " pbcopy for OSX copy/paste
  vmap <C-x> :!pbcopy<CR>
  vmap <C-c> :w !pbcopy<CR><CR>
endif

"" Include user's local vim config
if filereadable(expand("~/.vimrc.local"))
  source ~/.vimrc.local
endif

"*****************************************************************************
"" File Type Setting
"*****************************************************************************

"" ruby

autocmd BufNewFile,BufRead *.rb,*.rbw,*.gemspec setlocal filetype=ruby
autocmd Filetype ruby setlocal ts=2 sts=2 sw=2
