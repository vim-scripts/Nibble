" nibble.vim -- Nibble (also called snake) game for Vim
" Author: Hari Krishna (hari_vim at yahoo dot com)
" Last Change: 20-Feb-2004 @ 17:17
" Created: 06-Feb-2004
" Requires: Vim-6.2, multvals.vim(3.4), genutils.vim(1.10)
" Version: 1.1.0
" Licence: This program is free software; you can redistribute it and/or
"          modify it under the terms of the GNU General Public License.
"          See http://www.gnu.org/copyleft/gpl.txt 
" Acknowledgements:
"   - Thanks to Bram Moolenaar (Bram at moolenaar dot net) for reporting
"     problems and giving feedback.
" Download From:
"     http://www.vim.org/script.php?script_id=916
" Description:
" TODO:
"   - Investigate any possibilities for highlighting half-character vertically.
"   - It should be possible to support two players with two snakes.

if exists('loaded_nibble')
  call s:Nibble()
  finish
endif

if v:version < 602
  echomsg 'You need Vim 6.2 to run this version of nibble.vim.'
  finish
endif

" Dependency checks.
if !exists('loaded_multvals')
  runtime plugin/multvals.vim
endif
if !exists('loaded_multvals') || loaded_multvals < 304
  echomsg 'nibble: You need the latest version of multvals.vim plugin'
  finish
endif
if !exists('loaded_genutils')
  runtime plugin/genutils.vim
endif
if !exists('loaded_genutils') || loaded_genutils < 110
  echomsg 'nibble: You need the latest version of genutils.vim plugin'
  finish
endif
let loaded_nibble = 1

" Make sure line-continuations won't cause any problem. This will be restored
"   at the end
let s:save_cpo = &cpo
set cpo&vim

"command! Snake :call <SID>Nibble()

" Initialization {{{

if !exists('g:nibbleNoSplash')
  let g:nibbleNoSplash = 0
endif

if !exists('s:myBufNum')
  let s:myBufNum = -1

  " State variables.
  let s:level = 0
  let s:nLife = 0
  let s:score = 0
  let s:prevGoodScore = 0
  let s:aim = 0
  let s:ly = 0
  let s:lx = 0
  let s:playPaused = 0
endif

" Constants.
let s:MAX_LEVEL = 5
let s:s:MAX_LIVES = 3
let s:INIT_SNAKE_SIZE = 3
let s:START_LEVEL = 1
let s:MAX_AIM = 9

let s:GAME_PAUSED = 'G A M E   P A U S E D'

" Memory management.
let s:nSnakes = 0
let s:nLines = 0
let s:nBlocks = 0

" Initialization }}}

function! s:SetupBuf()
  let s:MAXX = winwidth(0)
  let s:MAXY = winheight(0)

  call s:clear()
  call SetupScratchBuffer()
  setlocal noreadonly " Or it shows [RO] after the buffer name, not nice.
  setlocal nonumber
  setlocal foldcolumn=0 nofoldenable
  setlocal tabstop=1
  setlocal bufhidden=hide

  " Setup syntax such a way that any non-tabs appear as selected.
  syn clear
  syn match NibbleSelected "[^\t]"
  hi NibbleSelected gui=reverse term=reverse cterm=reverse

  " Let pressing space again resume a paused game.
  nnoremap <buffer> <Space> :Nibble<CR>
endfunction

function! s:Nibble()
  if s:myBufNum == -1
    " Temporarily modify isfname to avoid treating the name as a pattern.
    let _isf = &isfname
    let _cpo = &cpo
    try
      set isfname-=\
      set isfname-=[
      set cpo-=A
      if exists('+shellslash')
	exec "sp \\\\[Nibble]"
      else
	exec "sp \\[Nibble]"
      endif
    finally
      let &isfname = _isf
      let &cpo = _cpo
    endtry
    let s:myBufNum = bufnr('%')
  else
    let buffer_win = bufwinnr(s:myBufNum)
    if buffer_win == -1
      exec 'sb '. s:myBufNum
    else
      exec buffer_win . 'wincmd w'
    endif
  endif
  wincmd _

  let restCurs = ''
  let _gcr = &guicursor
  try
    setlocal modifiable

    let restCurs = substitute(GetVimCmdOutput('hi Cursor'),
          \ '^\(\n\|\s\)*Cursor\s*xxx\s*', 'hi Cursor ', '')
    let hideCurs = substitute(GetVimCmdOutput('hi Normal'),
          \ '^\(\n\|\s\)*Normal\s*xxx\s*', 'hi Cursor ', '')
    " Font attribute for Cursor doesn't seem to be really used, and it might
    " cause trouble if has spaces in it, so just remove this attribute.
    let restCurs = substitute(restCurs, ' font=.\{-}\(\w\+=\|$\)\@=', ' ', '')
    let hideCurs = substitute(hideCurs, ' font=.\{-}\(\w\+=\|$\)\@=', ' ', '')

    let option = 'p'
    if !s:playPaused
      call s:SetupBuf()

      call s:welcome()
    endif

    exec hideCurs
    set guicursor=n-i:hor1:ver1
    call s:play()
  catch /^Vim:Interrupt$/
    " Do nothing.
  finally
    exec restCurs | " Restore the cursor highlighting.
    let &guicursor = _gcr
    if !s:playPaused
      call s:clearVars() 
    endif
    call setbufvar(s:myBufNum, '&modifiable', !s:playPaused)
  endtry
endfunction

function! s:welcome()
  if g:nibbleNoSplash
    return
  endif

  call s:clear()
  let y = s:MAXY/2 - 6
  call s:putstrcentered(y, 'N I B B L E   G A M E')
  call s:putstrcentered(y+3, 'F O R   V I M')
  call s:putstr(y+5, 1, "Use 'h', 'j', 'k' & 'l' keys to change the direction".
        \ "of the snake.")
  call s:putstr(y+7, 1, 'q or <ctrl>C to Quit and <Space> to Pause')
  redraw
  3sleep
endfunction

function! s:play()
  redraw
  if !s:playPaused
    let s:level = s:START_LEVEL
    let s:nLife = 0
    let s:score = 0
    let s:prevGoodScore = 0
    let s:aim = 0
    let s:ly = 0
    let s:lx = 0
  else
    call s:putstrcentered(1, substitute(s:GAME_PAUSED, '[^ ]', ' ', 'g'))
    redraw
    1sleep " Give time to react.
  endif
  let lostLife = 0
  while s:level <= s:MAX_LEVEL
    try " [-2f]

    if !s:playPaused
      if !s:InitLevel(s:level)
        break
      endif
      let s:prevGoodScore = s:score
      let s:aim = 0
      call s:SnakeSetSize(s:snake, s:INIT_SNAKE_SIZE)
    endif
    call s:showLives()
    while s:aim < s:MAX_AIM
      if !s:playPaused
        " Determine the random positions of the aim, between (2, MAX-1).
        let s:ly = (s:rand() % (s:MAXY-2)) + 2
        let s:lx = (s:rand() % (s:MAXX-2)) + 2
        " Skip this random position if it falls on the snake or block.
        if s:SnakePtOnSnake(s:snake, s:ly, s:lx) ||
              \ s:BlockPtOnBlock(s:blocks, s:ly, s:lx)
          continue
        endif
        let s:aim = s:aim + 1
      else
        let s:playPaused = 0
      endif
      call s:putstr(s:ly, s:lx, s:aim.'')
      while 1
        let char = getchar(0)
        if char == '^\d\+$' || type(char) == 0
          let char = nr2char(char)
        endif " It is the ascii code.

        if char == 'q'
          quit
          return
        elseif char == ' '
          let s:playPaused = 1
          call s:putstrcentered(1, s:GAME_PAUSED)
          return
        elseif char == 'k' " UP
          call s:SnakeUp(s:snake)
        elseif char == 'j' " DOWN
          call s:SnakeDown(s:snake)
        elseif char == 'l' " RIGHT
          call s:SnakeRight(s:snake)
        elseif char == 'h' " LEFT
          call s:SnakeLeft(s:snake)
        endif

        if !s:SnakeMove(s:snake)
          let lostLife = 1
          break
        endif
        let fx = s:SnakeHeadX(s:snake)
        let fy = s:SnakeHeadY(s:snake)
        " Snake touched the border, blocks or hit itself.
        if
              \ (fy <= 1 || fy >= s:MAXY || fx <= 1 || fx >= s:MAXX) ||
              \ s:BlockPtOnBlock(s:blocks, fy, fx)
          let lostLife = 1
          break
        endif
        if fy == s:ly && fx == s:lx " Snake ate the mouse.
          let s:score = s:score + s:level*s:aim*10
          call s:SnakeSetSize(s:snake, s:SnakeSize(s:snake)+2*s:aim)
          call s:ShowScore()
          break
        endif
        call s:delay()
      endwhile

      if lostLife
        if s:nLife != s:s:MAX_LIVES
          let lostLife = 0
          let s:nLife = s:nLife + 1
          let s:level = s:level - 1 " Play the same level again.
          let s:score = s:prevGoodScore
        endif
        break
      endif
    endwhile

    if lostLife
      break " Game end.
    endif
    finally " [+2s]
      if !s:playPaused
        let s:level = s:level + 1
      endif
    endtry
  endwhile
  call s:putstrcentered(s:MAXY/2 - 2, 'G A M E   E N D E D !!!')
endfunction

function! s:ShowScore()
  call s:putstrright(s:MAXY, 'Score: '.s:score)
endfunction

function! s:ShowLevel()
  call s:putstrcentered(s:MAXY, 'Level: '.s:level.'/'.s:MAX_LEVEL)
endfunction

function! s:showLives()
  call s:putstrleft(s:MAXY, 'Lives used: '.s:nLife.'/'.s:s:MAX_LIVES)
endfunction

let s:randSeed = substitute(strftime('%S'), '^0', '', '')+0
let s:randSeq = 0
function! s:rand()
  let randNew = substitute(strftime('%S'), '^0', '', '')+0
  let randNew = randNew + 60*(substitute(strftime('%S'), '^0', '', '')+0)
  let s:randSeq = s:randSeq + 1
  return s:randSeed + randNew + s:randSeq
endfunction

function! s:InitLevel(level)
  call s:clear()
  let y = s:MAXY/2 - 6
  let x = s:MAXX/2 - 12
  call s:putstrcentered(y, 'Continuing level '.a:level)
  call s:putstrcentered(y + 2, 'Push SPACE bar to quit...')
  redraw
  2sleep
  if getchar(0) == 32
    return 0
  endif

  call s:clear()
  " We have a border for all the levels.
  call s:putrow(1, 1, s:MAXX, ' ')
  call s:putrow(s:MAXY, 1, s:MAXX, ' ')
  call s:putcol(2, s:MAXY - 1, 1, ' ')
  call s:putcol(2, s:MAXY - 1, s:MAXX, ' ')
  let s:snake = s:SnakeCreate()

  let s:blocks = s:BlockCreate()
  if a:level == 2
    " One horizonal line in the middle.
    let width = s:MAXX*3/8
    let x = (s:MAXX-width)/2
    let y = s:MAXY/2
    call s:BlockAddHorLine(s:blocks, y, x, x+width)
  elseif a:level == 3
    " Two vertical lines in the middle.
    let width = s:MAXY*3/8
    let height = 2*width
    let x = s:MAXX/6
    let y = s:MAXY*5/16
    call s:BlockAddVerLine(s:blocks, y, y + width, x)
    call s:BlockAddVerLine(s:blocks, y, y + width, s:MAXX - x)
  elseif a:level == 4
    " A square looking rectagle in the middle, with only a small entrance.
    let width1 = s:MAXX*3/8
    let width2 = s:MAXY*3/8
    let x = s:MAXX*5/16
    let y = s:MAXY*5/16
    call s:BlockAddHorLine(s:blocks, y, x, x+width1)
    call s:BlockAddHorLine(s:blocks, y + width2, x, x+width1)
    call s:BlockAddVerLine(s:blocks, y, y + width2 - 2, x)
    call s:BlockAddVerLine(s:blocks, y, y + width2, x + width1)
  elseif a:level == 5
    " A Cross in the middle.
    let x = s:MAXX / 2
    let y = s:MAXY / 2
    call s:BlockAddHorLine(s:blocks, y, 3, s:MAXX - 2)
    call s:BlockAddVerLine(s:blocks, 3, s:MAXY - 2, x)
  endif

  call s:ShowScore()
  call s:ShowLevel()
  " Eat any pending characters.
  while getchar(0) != '0'
  endwhile
  return 1
endfunction

function! s:putrow(y, x1, x2, ch)
  let y = (a:y > 0) ? a:y : 1
  let x1 = (a:x1 > 0) ? a:x1 : 1
  let x2 = (a:x2 > 0) ? a:x2 : 1
  let x2 = (x2 == s:MAXX) ? x2 + 1 : x2
  let ch = a:ch[0]
  let _search = @/
  try
    let @/ = '\%>'.(x1-1).'c.\%<'.(x2+2).'c'
    silent! exec y.'s//'.ch.'/g'
  finally
    let @/ = _search
  endtry
endfunction

function! s:putcol(y1, y2, x, ch)
  let y1 = (a:y1 > 0) ? a:y1 : 1
  let y2 = (a:y2 > 0) ? a:y2 : 1
  let x = (a:x > 0) ? a:x : 1
  let ch = a:ch[0]
  let _search = @/
  try
    let @/ = '\%'.x.'c.'
    silent! exec y1.','.y2.'s//'.ch
  finally
    let @/ = _search
  endtry
endfunction

function! s:putstr(y, x, str)
  let y = (a:y > 0) ? a:y : 1
  let x = (a:x > 0) ? a:x : 1
  let _search = @/
  try
    if a:y > line('$')
      silent! $put=a:str
    else
      let @/ = '\%'.x.'c.\{'.strlen(a:str).'}'
      silent! exec y.'s//'.escape(a:str, '\&~/')
    endif
  finally
    let @/ = _search
  endtry
endfunction

function! s:putstrleft(y, str)
  call s:putstr(a:y, 2, a:str)
endfunction

function! s:putstrright(y, str)
  call s:putstr(a:y, s:MAXX-strlen(a:str)-1, a:str)
endfunction

function! s:putstrcentered(y, str)
  call s:putstr(a:y, (s:MAXX-strlen(a:str))/2, a:str)
endfunction

function! s:clear()
  call OptClearBuffer()
  " Fill the buffer with tabs.
  let tabFill = substitute(GetSpacer(s:MAXX), ' ', "\t", 'g')
  while strlen(tabFill) < s:MAXX
    let tabFill = tabFill.strpart(tabFill, 0, s:MAXX - strlen(tabFill))
  endwhile
  call setline(1, tabFill)
  let i = 2
  while i <= s:MAXY
    silent! $put=tabFill
    let i = i + 1
  endwhile 

  call s:clearVars()
endfunction

function! s:clearVars() 
  let i = 0
  while i < s:nSnakes
    call s:SnakeDestroy(i)
    let i = i + 1
  endwhile
  let s:nSnakes = 0

  let i = 0
  while i < s:nBlocks
    call s:BlockDestroy(i)
    let i = i + 1
  endwhile
  let s:nBlocks = 0

  let i = 0
  while i < s:nLines
    call s:LineDestroy(i)
    let i = i + 1
  endwhile
  let s:nLines = 0
endfunction

function! s:delay()
  sleep 80m
endfunction

function! s:numisnull(num)
  "return a:num.'' == ''
  return type(a:num)
endfunction

" Point {{{

function! s:PtCreate(y, x)
  return a:y.','.a:x
endfunction

function! s:PtX(pt)
  return matchstr(a:pt, '\d\+$')+0
endfunction

function! s:PtY(pt)
  return matchstr(a:pt, '^\d\+')+0
endfunction

" Point }}}

" Snake {{{

function! s:_SnakeCreate()
  let nextSnake = s:nSnakes
  let s:nSnakes = s:nSnakes + 1
  return nextSnake
endfunction

function! s:PtCreate(y, x)
  return a:y.','.a:x
endfunction

function! s:SnakeCreate()
  let snake = s:_SnakeCreate()
  let s:snake{snake}{'size'} = 0 " Target size of the snake.
  let s:snake{snake}{'sizeI'} = 0 " Current temporal size of the snake.
  let s:snake{snake}{'points'} = ''
  let s:snake{snake}{'headx'} = ''
  let s:snake{snake}{'heady'} = ''
  let s:snake{snake}{'tailx'} = ''
  let s:snake{snake}{'taily'} = ''
  let s:snake{snake}{'incrx'} = 1 " Determines the x direction of the snake.
  let s:snake{snake}{'incry'} = 0 " Determines the y direction of the snake.

  call s:SnakeAddHead(snake, 2, 2)
  return snake
endfunction

function! s:SnakeDestroy(snake)
  silent! unlet s:snake{snake}{'size'} s:snake{snake}{'sizeI'}
        \ s:snake{snake}{'headx'} s:snake{snake}{'tailx'}
        \ s:snake{snake}{'heady'} s:snake{snake}{'taily'}
        \ s:snake{snake}{'incrx'} s:snake{snake}{'incry'}
        \ s:snake{snake}{'points'}
endfunction

function! s:SnakeSize(snake)
  return s:snake{a:snake}{'size'}
endfunction

function! s:SnakeSizeI(snake)
  return s:snake{a:snake}{'sizeI'}
endfunction

function! s:SnakeIncrX(snake)
  return s:snake{a:snake}{'incrx'}
endfunction

function! s:SnakeIncrY(snake)
  return s:snake{a:snake}{'incry'}
endfunction

function! s:SnakeHeadX(snake)
  return s:snake{a:snake}{'headx'}
endfunction

function! s:SnakeHeadY(snake)
  return s:snake{a:snake}{'heady'}
endfunction

function! s:SnakeTailX(snake)
  return s:snake{a:snake}{'tailx'}
endfunction

function! s:SnakeTailY(snake)
  return s:snake{a:snake}{'taily'}
endfunction

function! s:SnakePoints(snake)
  return s:snake{a:snake}{'points'}
endfunction

function! s:SnakeSetSize(snake, size)
  let s:snake{a:snake}{'size'} = a:size
endfunction

function! s:SnakeSetSizeI(snake, size)
  let s:snake{a:snake}{'sizeI'} = a:size
endfunction

function! s:SnakeSetHeadX(snake, headx)
  let s:snake{a:snake}{'headx'} = a:headx
endfunction

function! s:SnakeSetHeadY(snake, heady)
  let s:snake{a:snake}{'heady'} = a:heady
endfunction

function! s:SnakeSetTail(snake, tail)
  call s:SnakeSetTailX(a:snake, s:PtX(a:tail))
  call s:SnakeSetTailY(a:snake, s:PtY(a:tail))
endfunction

function! s:SnakeSetTailX(snake, tailx)
  let s:snake{a:snake}{'tailx'} = a:tailx
endfunction

function! s:SnakeSetTailY(snake, taily)
  let s:snake{a:snake}{'taily'} = a:taily
endfunction

function! s:SnakeSetIncrX(snake, incrx)
  let s:snake{a:snake}{'incrx'} = a:incrx
endfunction

function! s:SnakeSetIncrY(snake, incry)
  let s:snake{a:snake}{'incry'} = a:incry
endfunction

function! s:SnakeSetPoints(snake, points)
  let s:snake{a:snake}{'points'} = a:points
endfunction

function! s:SnakeAddHead(snake, y, x)
  let newPt = s:PtCreate(a:y, a:x)
  call s:putstr(a:y, a:x, ' ')
  call s:SnakeSetPoints(a:snake,
        \ MvAddElement(s:SnakePoints(a:snake), ';', newPt))
  call s:SnakeSetHeadY(a:snake, a:y)
  call s:SnakeSetHeadX(a:snake, a:x)
  if s:numisnull(s:SnakeTailY(a:snake))
    call s:SnakeSetTailY(a:snake, a:y)
    call s:SnakeSetTailX(a:snake, a:x)
  endif
  call s:SnakeSetSizeI(a:snake, s:SnakeSizeI(a:snake) + 1)
endfunction

function! s:SnakeRemoveTail(snake)
  let taily = s:SnakeTailY(a:snake)
  let tailx = s:SnakeTailX(a:snake)
  call s:SnakeSetPoints(a:snake,
        \ MvRemoveElementAt(s:SnakePoints(a:snake), ';', 0))
  call s:SnakeSetTail(a:snake, MvElementAt(s:SnakePoints(a:snake), ';', 0))
  call s:SnakeSetSizeI(a:snake, s:SnakeSizeI(a:snake) - 1)
  call s:putstr(taily, tailx, "\t")
endfunction

function! s:SnakeUp(snake)
  if s:SnakeIncrY(a:snake) == -1 || s:SnakeIncrY(a:snake) == 1
    return
  endif
  call s:SnakeSetIncrX(a:snake, 0)
  call s:SnakeSetIncrY(a:snake, -1)
endfunction

function! s:SnakeDown(snake)
  if s:SnakeIncrY(a:snake) == -1 || s:SnakeIncrY(a:snake) == 1
    return
  endif
  call s:SnakeSetIncrX(a:snake, 0)
  call s:SnakeSetIncrY(a:snake, 1)
endfunction

function! s:SnakeRight(snake)
  if s:SnakeIncrX(a:snake) == -1 || s:SnakeIncrX(a:snake) == 1
    return
  endif
  call s:SnakeSetIncrX(a:snake, 1)
  call s:SnakeSetIncrY(a:snake, 0)
endfunction

function! s:SnakeLeft(snake)
  if s:SnakeIncrX(a:snake) == -1 || s:SnakeIncrX(a:snake) == 1
    return
  endif
  call s:SnakeSetIncrX(a:snake, -1)
  call s:SnakeSetIncrY(a:snake, 0)
endfunction

function! s:SnakeMove(snake)
  let fx = s:SnakeHeadX(a:snake) + s:SnakeIncrX(a:snake)
  let fy = s:SnakeHeadY(a:snake) + s:SnakeIncrY(a:snake)
  let head = s:PtCreate(fy, fx)
  let points = s:SnakePoints(a:snake)
  if MvContainsElement(points, ';', head) " Snake hit itself.
    return 0
  endif
  call s:SnakeAddHead(a:snake, fy, fx)
  if s:SnakeSizeI(a:snake) > s:SnakeSize(a:snake)
    " Remove the tail.
    call s:SnakeRemoveTail(a:snake)
  endif
  redraw
  return 1
endfunction

function! s:SnakePtOnSnake(snake, y, x)
  let pt = s:PtCreate(a:y, a:x)
  let points = s:SnakePoints(a:snake)
  if MvContainsElement(strpart(points, 0, strlen(points) - 1 - strlen(pt)), ';',
        \ pt)
    return 1
  endif
  return 0
endfunction

" Snake }}}

" Block {{{

function! s:_BlockCreate()
  let nextBlock = s:nBlocks
  let s:nBlocks = s:nBlocks + 1
  return nextBlock
endfunction

function! s:BlockCreate()
  let block = s:_BlockCreate()
  let s:block{block}{'tail'} = ''
  let s:block{block}{'head'} = ''
endfunction

function! s:BlockDestroy(block)
  unlet s:block{a:block}{'tail'}
endfunction

function! s:BlockHead(block)
  return s:block{a:block}{'head'}
endfunction

function! s:BlockTail(block)
  return s:block{a:block}{'tail'}
endfunction

function! s:BlockSetHead(block, head)
  let s:block{a:block}{'head'} = a:head
endfunction

function! s:BlockSetTail(block, tail)
  let s:block{a:block}{'tail'} = a:tail
endfunction

function! s:_BlockAddLine(block, line)
  let oldHead = s:BlockHead(a:block)
  if ! s:numisnull(oldHead)
    call s:LineSetNext(oldHead, a:line)
  else
    call s:BlockSetTail(a:block, a:line)
  endif
  call s:BlockSetHead(a:block, a:line)
endfunction

function! s:BlockAddHorLine(block, y, x1, x2)
  call s:_BlockAddLine(a:block, s:LineCreateHor(a:y, a:x1, a:x2))
  call s:putrow(a:y, a:x1, a:x2, ' ')
endfunction

function! s:BlockAddVerLine(block, y1, y2, x)
  call s:_BlockAddLine(a:block, s:LineCreateVer(a:y1, a:y2, a:x))
  call s:putcol(a:y1, a:y2, a:x, ' ')
endfunction

function! s:BlockPtOnBlock(block, y, x)
  let line = s:BlockTail(a:block)
  while ! s:numisnull(line)
    if s:LinePtOnLine(line, a:y, a:x)
      return 1
    endif
    let line = s:LineNext(line)
  endwhile
  return 0
endfunction

" Block }}}

" Line {{{

function! s:__LineCreate()
  let nextLines = s:nLines
  let s:nLines = s:nLines + 1
  return nextLines
endfunction

" y1 <= y2 && x1 <= x2
function! s:_LineCreate(y1, x1, y2, x2)
  let line = s:__LineCreate()
  let s:line{line}{'y1'} = a:y1
  let s:line{line}{'x1'} = a:x1
  let s:line{line}{'y2'} = a:y2
  let s:line{line}{'x2'} = a:x2
  let s:line{line}{'next'} = ''
  return line
endfunction

function! s:LineCreateHor(y, x1, x2)
  return s:_LineCreate(a:y, a:x1, a:y, a:x2)
endfunction

function! s:LineCreateVer(y1, y2, x)
  return s:_LineCreate(a:y1, a:x, a:y2, a:x)
endfunction

function! s:LineDestroy(line)
  unlet s:line{a:line}{'y1'} s:line{a:line}{'x1'} s:line{a:line}{'y2'}
        \ s:line{a:line}{'x2'} s:line{a:line}{'next'}
endfunction

function! s:LineY1(line)
  return s:line{a:line}{'y1'}
endfunction

function! s:LineX1(line)
  return s:line{a:line}{'x1'}
endfunction

function! s:LineY2(line)
  return s:line{a:line}{'y2'}
endfunction

function! s:LineX2(line)
  return s:line{a:line}{'x2'}
endfunction

function! s:LineNext(line)
  return s:line{a:line}{'next'}
endfunction

function! s:LineSetNext(line, next)
  let s:line{a:line}{'next'} = a:next
endfunction

function! s:LinePtOnLine(line, y, x)
  return s:LineY1(a:line) <= a:y && a:y <= s:LineY2(a:line) &&
        \s:LineX1(a:line) <= a:x && a:x <= s:LineX2(a:line)
endfunction

" Line }}}


" Restore cpo.
let &cpo = s:save_cpo
unlet s:save_cpo

" vim6:fdm=marker et sw=2
