if !has('python3')
    echohl ErrorMsg | echomsg 'PyGithubDiary: python3 is required but not available.' | echohl None
    finish
endif

function! s:Diary_createDiaryInst()
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
endfunction

function! s:DiaryFunc_create()
    call s:Diary_createDiaryInst()

    tabnew
    norm gg

    put! =py3eval('g_diaryInst.create_content()')

    norm G
    let t:PyGithubDiary_tab_opened = 1
endfunction

function! s:DiaryFunc_submit()
    if exists('t:PyGithubDiary_tab_opened')
        if wordcount()['bytes'] >= 100 * 1024 * 1024
            echohl ErrorMsg | echomsg 'PyGithubDiary: can not submit file size greater than 100MBytes.' | echohl None
            return
        endif

        let l:py_cmd = printf('g_diaryInst.submit(%s%s%s)', '"""', join(getline(1, '$'), '\n'), '"""')
        call py3eval(l:py_cmd)

        unlet t:PyGithubDiary_tab_opened
        q!
    else
        echohl ErrorMsg | echomsg 'PyGithubDiary: current tab is not opened to submit diary.' | echohl None
    end
endfunction

function! s:DiaryFunc_viewText(regfile)
    call s:Diary_createDiaryInst()

    tabnew
    norm gg

    let l:py_cmd = printf('g_diaryInst.view_text(%s%s%s)', '"""', a:regfile, '"""')
    put! =py3eval(l:py_cmd)

    norm gg
endfunction

function! s:DiaryFunc_viewHtml(regfile)
    call s:Diary_createDiaryInst()

    tabnew
    norm gg

    let l:py_cmd = printf('g_diaryInst.view_html(%s%s%s)', '"""', a:regfile, '"""')
    put! =py3eval(l:py_cmd)

    set filetype=html
    norm gg
endfunction

command!          DiaryCreate   :call s:DiaryFunc_create()
command!          DiarySubmit   :call s:DiaryFunc_submit()
command! -nargs=1 DiaryViewText :call s:DiaryFunc_viewText(<q-args>)
command! -nargs=1 DiaryViewHtml :call s:DiaryFunc_viewHtml(<q-args>)
