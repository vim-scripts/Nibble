" nibble.vim -- Nibble (or snake) game for Vim
" Author: Hari Krishna (hari_vim at yahoo dot com)
" Last Change: 09-Feb-2004 @ 12:33
" Created: 06-Feb-2004
" Version: 1.0.0
" Licence: This program is free software; you can redistribute it and/or
"          modify it under the terms of the GNU General Public License.
"          See http://www.gnu.org/copyleft/gpl.txt 
" Download From:
"     http://www.vim.org/script.php?script_id=
" Description:
"   This is just a quick-loader for the Nibble game, see
"   games/nibble/nibble.vim for the actual code.
"
"   Use hjkl keys to move the snake. Use <Space> to pause the play. Use <C-C>
"   to stop the play at any time.

command! -nargs=? Nibble :call <SID>Nibble(<args>)

function! s:Nibble(...)
  if !exists('g:loaded_nibble')
    " If it is not already loaded, first load it.
    runtime games/nibble/nibble.vim
  endif
  "let g:hanoiNDisks = (a:0 > 0) ? a:1 : ''
  runtime games/nibble/nibble.vim
endfunction

