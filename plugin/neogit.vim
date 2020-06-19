lua neogit = require("neogit")

let s:change_regex = "^modified \\(.*\\)$"

function! s:neogit_get_hovered_file()
  let line = getline('.')
  let matches = matchlist(line, s:change_regex)

  if len(matches) == 0
    return v:null
  endif

  return matches[1]
endfunction

function! s:neogit_toggle()
  setlocal modifiable

  let file = s:neogit_get_hovered_file()

  if file == v:null 
    return
  endif

  let section = s:neogit_get_hovered_section()

  let change_idx = line('.') - section.start - 1
  let change = s:state.status[section.name][change_idx]

  if change.diff_open == v:true 
    let change.diff_open = v:false

    normal j
    silent execute 'normal ' change.diff_height . 'dd'
    normal k

    let section.end = section.end - change.diff_height
  else
    let result = systemlist("git diff " . file)
    let diff = result[4:-1]

    let change.diff_open = v:true
    let change.diff_height = len(diff) 

    let section.end = section.end + change.diff_height

    call append('.', diff)
  endif

  setlocal nomodifiable
endfunction

function! s:neogit_get_hovered_section_idx()
  let line = line('.')
  let i = 0
  let idx = -1

  for location in s:state.locations
    if location.start <= line && line <= location.end
      let idx = i
      break
    endif
    let i = i + 1
  endfor

  return idx
endfunction

function! s:neogit_get_hovered_section()
  return s:state.locations[s:neogit_get_hovered_section_idx()]
endfunction

function! s:neogit_move_to_section(step)
  let idx = s:neogit_get_hovered_section_idx()

  if a:step < 0 && idx == -1 
    let idx = 0
  endif

  if len(s:state.locations) == idx + a:step
    let idx = -1
  endif

  call cursor(s:state.locations[idx + a:step].start, 0)
endfunction

function! s:neogit_move_to_item(step)
  let section = s:neogit_get_hovered_section()
  let file = s:neogit_get_hovered_file()
  let line = line('.')

  if file != v:null 
    if a:step > 0
      if line < section.end
        silent execute 'normal ' . a:step . 'j'
      endif
    else
      if line > section.start + 1
        silent execute 'normal ' . (a:step * -1) . 'k'
      endif
    endif
  endif
endfunction

function! s:neogit_next_item()
  call s:neogit_move_to_item(1)
endfunction

function! s:neogit_prev_item()
  call s:neogit_move_to_item(-1)
endfunction

function! s:neogit_next_section()
  call s:neogit_move_to_section(1)
endfunction

function! s:neogit_prev_section()
  call s:neogit_move_to_section(-1)
endfunction

function! s:neogit_stage_all()
  call system("git add " . join(map(s:state.status.unstaged_changes, {_, val -> val.file}), " "))
  call s:neogit_refresh_status()
endfunction

function! s:neogit_unstage_all()
  call system("git reset")
  call s:neogit_refresh_status()
endfunction

function! s:neogit_stage()
  let file = s:neogit_get_hovered_file()

  if file != v:null
    call system("git add " . file)
    call s:neogit_refresh_status()
  endif
endfunction

function! s:neogit_unstage()
  let file = s:neogit_get_hovered_file()

  if file != v:null
    call system("git reset " . file)
    call s:neogit_refresh_status()
  endif
endfunction

function! s:neogit_refresh_status()
  setlocal modifiable

  let line = line('.')
  let col = col('.')

  call feedkeys('gg', 'x')
  call feedkeys('dG', 'x')
  call s:neogit_print_status()

  call cursor([line, col])
endfunction

function! s:neogit_print_status()
  setlocal modifiable

  let status = luaeval("neogit.status()")
  let stashes = luaeval("neogit.stashes()")
  let s:lineidx = 0

  let s:state = {
        \ "status": status,
        \ "stashes": stashes,
        \ "locations": []
        \}

  function! Write(str)
    call append(s:lineidx, a:str)
    let s:lineidx = s:lineidx + 1
  endfunction

  call Write("Head: " . status.branch)
  call Write("Push: " . status.remote)

  if len(status.unstaged_changes) != 0
    call Write("")
    call Write("Unstaged changes (" . len(status.unstaged_changes) . ")")
    let start = s:lineidx
    for change in status.unstaged_changes
      call Write(change.type . " " . change.file)
    endfor
    let end = s:lineidx
    call add(s:state.locations, {
          \ "name": "unstaged_changes",
          \ "start": start,
          \ "end": end
          \})
  endif

  if len(status.staged_changes) != 0
    call Write("")
    call Write("Staged changes (" . len(status.staged_changes) . ")")
    let start = s:lineidx
    for change in status.staged_changes
      call Write(change.type . " " . change.file)
    endfor
    let end = s:lineidx
    call add(s:state.locations, {
          \ "name": "staged_changes",
          \ "start": start,
          \ "end": end
          \})
  endif

  if len(stashes) != 0
    call Write("")
    call Write("Stashes (" . len(stashes) . ")")
    let start = l:lineidx
    for stash in stashes
      call Write("stash@{" . stash.idx . "} " . stash.name)
    endfor
    let end = s:lineidx
    call add(s:state.locations, {
          \ "name": "stashes",
          \ "start": start,
          \ "end": end
          \})
  endif

  if status.behind_by != 0
    call Write("")
    call Write("Unpulled from " . status.remote . " (" . status.behind_by . ")")
    let start = s:lineidx

    let commits = luaeval("neogit.unpulled('" . status.remote . "')")

    for commit in commits
      call Write(commit)
    endfor
    let end = s:lineidx
    call add(s:state.locations, {
          \ "name": "unpulled",
          \ "start": start,
          \ "end": end
          \})
  endif

  if status.ahead_by != 0
    call Write("")
    call Write("Unmerged into " . status.remote . " (" . status.ahead_by . ")")
    let start = s:lineidx
    let commits = luaeval("neogit.unmerged('" . status.remote . "')")

    for commit in commits
      call Write(commit)
    endfor
    let end = s:lineidx
    call add(s:state.locations, {
          \ "name": "unmerged",
          \ "start": start,
          \ "end": end
          \})
  endif
endfunction

function! s:neogit_push()
  !git push
  call s:neogit_refresh_status()
endfunction

function! s:neogit_commit()
endfunction

function! s:neogit()
  enew

  call s:neogit_print_status()

  setlocal nomodifiable
  setlocal nohidden
  setlocal noswapfile
  setlocal nobuflisted

  nnoremap <buffer> <silent> q :bp!\|bd!#<CR>
  nnoremap <buffer> <silent> pp :call <SID>neogit_push()<CR>
  nnoremap <buffer> <silent> cc :call <SID>neogit_commit()<CR>
  nnoremap <buffer> <silent> s :call <SID>neogit_stage()<CR>
  nnoremap <buffer> <silent> S :call <SID>neogit_stage_all()<CR>
  nnoremap <buffer> <silent> <m-n> :call <SID>neogit_next_section()<CR>
  nnoremap <buffer> <silent> <m-p> :call <SID>neogit_prev_section()<CR>
  nnoremap <buffer> <silent> <c-n> :call <SID>neogit_next_item()<CR>
  nnoremap <buffer> <silent> <c-p> :call <SID>neogit_prev_item()<CR>
  nnoremap <buffer> <silent> u :call <SID>neogit_unstage()<CR>
  nnoremap <buffer> <silent> U :call <SID>neogit_unstage_all()<CR>
  nnoremap <buffer> <silent> <TAB> :call <SID>neogit_toggle()<CR>
endfunction

command! -nargs=0 Neogit call <SID>neogit()

Neogit