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


function! s:Diary_fakeDiaryName(filename)
    return printf('- PyGithubDiary - %s', a:filename)
endfunction


function! s:Diary_getBufferContent()
    return getline(1, '$')->join('\n')->substitute('"', '\\"', 'g')->substitute("'", "\\'", 'g')->substitute('\zs\\\ze[^n]', '\\\\', 'g')
endfunction


function! s:Diary_createBuffer(filename)
    if bufname() == '' && wordcount()['bytes'] == 0
        execute printf('file! %s', a:filename)
    else
        execute printf('bad +0 %s', a:filename)
        execute printf('buffer %s', a:filename)
    endif

    " disable file write
    " :write doesn't work, while :write <filename> does work

    setlocal buftype=nofile
    setlocal bufhidden=hide
    setlocal noswapfile
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

try:
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

except Exception as e:
    g_diaryInstError = str(e)

else:
    g_diaryInstError = None

PY3_EOF

    let l:err = py3eval('g_diaryInstError')
    if l:err == v:null
        return v:true
    else
        call s:Diary_echoError(l:err)
        return v:false
    endif
endfunction


function! s:DiaryFunc_openComplete(A, L, P)
    if !s:Diary_createDiaryInst()
        return
    endif

    let l:res = printf('g_diaryInst.export_listDiaries("%s", "%s", "%s")', a:A, a:L, a:P)->py3eval()
    if !l:res[0]
        call s:Diary_echoError(l:res[1])
        return
    endif

    return l:res[1]
endfunction


function! s:DiaryFunc_open(filename, newmode)
    if !s:Diary_createDiaryInst()
        return
    endif

    for l:ibuf in getbufinfo({'buflisted':1})
        let l:idx_found = stridx(l:ibuf['name'], s:Diary_fakeDiaryName(a:filename))
        if l:idx_found >= 0 && l:idx_found + len(s:Diary_fakeDiaryName(a:filename)) == len(l:ibuf['name'])
            execute printf('buffer %s', s:Diary_fakeDiaryName(a:filename))
            call s:Diary_echoError(printf('diary %s has already been opened', a:filename))
            return
        endif
    endfor

    let l:res = printf('g_diaryInst.export_getContent("%s", newmode=%s)', a:filename, a:newmode ? 'True' : 'False')->py3eval()
    if !l:res[0]
        call s:Diary_echoError(l:res[1])
        return
    endif

    call s:Diary_createBuffer(s:Diary_fakeDiaryName(a:filename))

    norm gg
    put! =l:res[1]

    if !a:newmode
        setlocal nomodifiable
    endif

    norm G
    let b:PyGithubDiary_buffer_opened = s:Diary_fakeDiaryName(a:filename)
endfunction


function! s:DiaryFunc_submit()
    if !exists('b:PyGithubDiary_buffer_opened')
        call s:Diary_echoError('current tab is not opened to submit diary')
        return
    endif

    if b:PyGithubDiary_buffer_opened != bufname()
        call s:Diary_echoError(printf('rename diary name to "%s" and try again', b:PyGithubDiary_buffer_opened))
        return
    endif

    if wordcount()['bytes'] >= 100 * 1024 * 1024
        call s:Diary_echoError('can not submit file size greater than 100 mbytes')
        return
    endif

    let l:content = s:Diary_getBufferContent()
    let l:filename = expand('%:t')->trim()->matchstr('\d\{4\}\.\d\{2\}\.\d\{2\}\.txt')

    let l:res = printf('g_diaryInst.export_submitContent(%s%s%s, filename="%s")', '"""', l:content, '"""', l:filename)->py3eval()
    if !l:res[0]
        call s:Diary_echoError(l:res[1])
        return
    endif

    unlet b:PyGithubDiary_buffer_opened
    bwipeout!
endfunction


function! s:DiaryFunc_viewText(regfile)
    if !s:Diary_createDiaryInst()
        return
    endif

    call s:Diary_createBuffer(strftime('view.%Y.%m.%d.%H.%M.%S.txt'))

    let l:res = printf('g_diaryInst.export_viewText(%s%s%s)', '"""', a:regfile, '"""')->py3eval()
    if !l:res[0]
        call s:Diary_echoError(l:res[1])
        return
    endif

    put! =l:res[1]
    norm gg

    setlocal nomodifiable
endfunction


function! s:DiaryFunc_viewHtml(regfile)
    if !s:Diary_createDiaryInst()
        return
    endif

    call s:Diary_createBuffer(strftime('view.%Y.%m.%d.%H.%M.%S.html'))

    let l:res = printf('g_diaryInst.export_viewHtml(%s%s%s)', '"""', a:regfile, '"""')->py3eval()
    if !l:res[0]
        call s:Diary_echoError(l:res[1])
        return
    endif

    put! =l:res[1]
    norm gg

    setlocal filetype=html
    setlocal nomodifiable
endfunction


command! DiaryNew :call s:DiaryFunc_open(strftime('%Y.%m.%d.txt'), v:true)
command! -nargs=1 -complete=customlist,s:DiaryFunc_openComplete DiaryOpen :call s:DiaryFunc_open(<q-args>, v:false)

command! DiarySubmit :call s:DiaryFunc_submit()

command! -nargs=1 DiaryViewText :call s:DiaryFunc_viewText(<q-args>)
command! -nargs=1 DiaryViewHtml :call s:DiaryFunc_viewHtml(<q-args>)

hightlight! link DiaryTimestamp Title
syntax match DiaryTimestamp /^\d\{4\}-\d\{2\}-\d\{2\} \d\{2\}:\d\{2\}:\d\{2\}\.\d\{6\} [MTWFS].\{-\}day wrote:$/
