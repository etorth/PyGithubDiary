if !has('python3')
    echohl ErrorMsg | echomsg 'PyGithubDiary: python3 is required but not available' | echohl None
    finish
endif


function! s:Diary_echoError(msg)
    if type(a:msg) == v:t_string
        echohl ErrorMsg | echomsg 'PyGithubDiary: ' . a:msg | echohl None
    else
        echohl ErrorMsg | echomsg 'PyGithubDiary: ' . string(a:msg) | echohl None
    endif
endfunction


function! s:Diary_createDiaryInst()
    " disable this check because of pynvim bug
    "
    "     https://github.com/neovim/pynvim/pull/496
    "
    " till now the fix has not been enabled

    " if py3eval('"PyGithubDiary_testString"') != 'PyGithubDiary_testString'
    "     call s:Diary_echoError('python interpreter does not work')
    "     return v:false
    " endif

python3 << PY3_EOF

import os
import PyGithubDiary

if 'g_diaryInst' not in locals():
    try:
        homeDir = os.environ['HOME']
    except KeyError:
        homeDir = os.environ['HomePath']
    except:
        raise RuntimeError('No valid home path configured in os envs')

    jsonPath = homeDir + '/.diary.json'
    if not os.path.isfile(jsonPath):
        raise RuntimeError('Config file does not exist: %s' % jsonPath)

    g_diaryInst = PyGithubDiary.Diary(jsonPath)

PY3_EOF

return v:true
endfunction


function! s:DiaryFunc_create()
    if !s:Diary_createDiaryInst()
        return
    endif

    let l:res = 'g_diaryInst.export_createContent()'->py3eval()
    if !l:res[0]
        call s:Diary_echoError(l:res[1])
        return
    endif

    tabnew
    norm gg

    put! =l:res[1]

    norm G
    let t:PyGithubDiary_tab_opened = 1
endfunction


function! s:DiaryFunc_submit()
    if !exists('t:PyGithubDiary_tab_opened')
        call s:Diary_echoError('current tab is not opened to submit diary')
        return
    endif

    if wordcount()['bytes'] >= 100 * 1024 * 1024
        call s:Diary_echoError('can not submit file size greater than 100 mbytes')
        return
    endif

    let l:res = printf('g_diaryInst.export_submitContent(%s%s%s)', '"""', substitute(join(getline(1, '$'), '\n'), '"', '\\"', 'g'), '"""')->py3eval()
    if !l:res[0]
        call s:Diary_echoError(l:res[1])
        return
    endif

    unlet t:PyGithubDiary_tab_opened
    q!
endfunction


function! s:DiaryFunc_viewText(regfile)
    if !s:Diary_createDiaryInst()
        return
    endif

    tabnew
    norm gg

    let l:res = printf('g_diaryInst.export_viewText(%s%s%s)', '"""', a:regfile, '"""')->py3eval()
    if !l:res[0]
        call s:Diary_echoError(l:res[1])
        return
    endif

    put! =l:res[1]
    norm gg
endfunction


function! s:DiaryFunc_viewHtml(regfile)
    if !s:Diary_createDiaryInst()
        return
    endif

    tabnew
    norm gg

    let l:res = printf('g_diaryInst.export_viewHtml(%s%s%s)', '"""', a:regfile, '"""')->py3eval()
    if !l:res[0]
        call s:Diary_echoError(l:res[1])
        return
    endif

    put! =l:res[1]
    norm gg

    set filetype=html
endfunction


command!          DiaryCreate   :call s:DiaryFunc_create()
command!          DiarySubmit   :call s:DiaryFunc_submit()
command! -nargs=1 DiaryViewText :call s:DiaryFunc_viewText(<q-args>)
command! -nargs=1 DiaryViewHtml :call s:DiaryFunc_viewHtml(<q-args>)
