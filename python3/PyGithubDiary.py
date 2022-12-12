import os
import re
import zlib
import json
import html
import base64
import github
import socket
import datetime
import traceback
import threading
import collections
import concurrent.futures


class Diary:


    def __init__(self, json_path):
        with open(json_path) as json_file:
            self.config = json.load(json_file)

            self.config.setdefault('timeout', 30)
            self.config.setdefault('log-path', None)
            self.config.setdefault('diary-repository', 'diary')
            self.config.setdefault('use-base64-encryption', True)
            self.config.setdefault('allow-public-repository', False)

            if self.config['timeout'] <= 0:
                self.config['timeout'] = 3600

            if self.config['log-path']:
                self.logLock = threading.Lock()
                self.logFile = open(self.config['log-path'], 'a')

            self.log('PyGithubDiary starts with PID %d' % os.getpid())
            self.log('')

            try:
                self.gh = github.Github(self.config['github-token'], timeout=self.config['timeout'])
            except github.BadCredentialsException:
                raise ValueError('invalid github token')

            try:
                self.repo_handler = self.gh.get_user().get_repo(self.config['diary-repository'])
            except github.UnknownObjectException:
                self.repo_handler = self.gh.get_user().create_repo(self.config['diary-repository'], description='Created by etorth/PyGithubDiary', private=True, auto_init=True)

            if (not self.config['allow-public-repository']) and (not self.repo_handler.private):
                raise ValueError('%s/%s is a public repository, set \'allow-public-repository\' as true to bypass' % (self.gh.get_user().login, self.config['diary-repository']))


    def log(self, msg: str):
        if self.config['log-path']:
            timestamp = self.now()
            lines = msg.splitlines()

            # don't do strip for lines
            # if there are unexpected blankspaces, it means content itself needs update

            self.logLock.acquire()
            for line in lines:
                if line:
                    self.logFile.write('%s: %s\n' % (timestamp, line))
                else:
                    self.logFile.write('%s:\n' % timestamp)
            self.logLock.release()


    def today(self) -> str:
        return datetime.date.today().strftime("%Y.%m.%d")


    def yesterday(self) -> str:
        return (datetime.date.today() - datetime.timedelta(days=1)).strftime("%Y.%m.%d")


    def today_file_name(self):
        return self.today() + ".txt"


    def now(self):
        return str(datetime.datetime.now())


    def weekday(self):
        return datetime.date.today().strftime("%A")


    def title(self):
        return self.now() + " " + self.weekday() + " wrote:"


    def pull_file_content(self, file_handler, name_pattern):
        if file_handler.type == 'dir':
            raise ValueError('unexpected directory %s' % file_handler.path)
        elif file_handler.path.endswith('.txt') and name_pattern.fullmatch(file_handler.path[:-4]):
            # pull diary file content and decode
            # done call .strip() before .decode(), tailing '\n' works as non-compression marker
            return (file_handler.path, self.decode(self.get_file_handler_content(file_handler)))


    def get_file_handler_content(self, file_handler) -> str:
        if file_handler.encoding == 'base64':
            return file_handler.decoded_content.decode("utf-8")
        else:
            # github doesn't support to directly retrieve large files > 1 MBytes
            # use blob type to retrieve file content
            #
            #   https://github.com/PyGithub/PyGithub/issues/661
            #
            # but still, currently gitbub doesn't support file > 100 MBytes
            #
            #   https://docs.github.com/en/rest/repos/contents
            #
            # see section of 'size limit'
            #
            # if oneday this method still not working, try following way
            #
            #   curl -H 'Accept: application/vnd.github.raw' \
            #        -H 'Authorization: token <your-github-token>' \
            #        'https://raw.githubusercontent.com/etorth/diary/main/2022.12.09.txt'
            #
            # where the url is from: ContentFile.download_url
            # in python use package 'requests' instead of using the curl binary
            return base64.b64decode(self.repo_handler.get_git_blob(file_handler.sha).content).decode('utf-8')


    def pull_diaries(self, regname) -> list:
        try:
            file_handlers = self.repo_handler.get_contents('')
        except github.UnknownObjectException:
            return []
        else:
            if regname == 'today':
                regname = self.today()

            elif regname == 'yesterday':
                regname = self.yesterday()

            feats = []
            file_pattern = re.compile(regname)

            with concurrent.futures.ThreadPoolExecutor() as executor:
                while len(file_handlers) > 0:
                    feats.append(executor.submit(self.pull_file_content, file_handlers.pop(0), file_pattern))

            # keep it if file exists but is empty
            # this ensures to keep an entry when file name matches
            return [f.result() for f in feats if f.result() is not None]


    def translate_content(self, content: str) -> str:
        pattern_imgpath = re.compile('^\s*\[\[img\s+?(\S+)\s*\]\]\s*$')
        translated_lines = []
        for line in content.splitlines():
            matched_imgpath = pattern_imgpath.match(line)
            if matched_imgpath:
                try:
                    with open(matched_imgpath.group(1), 'rb') as f:
                        # didn't put image type here
                        # should be data:image/png;base64,<base64-text-stream>

                        # didn't replace tailing '=' by '%3D', chrome looks still working
                        # but this web does replacement: https://greywyvern.com/code/php/binary2base64
                        translated_lines.append('[[imgbase64 data:image;base64,%s]]' % base64.b64encode(f.read()).decode('utf-8'))
                except:
                    translated_lines.append(line)
            else:
                translated_lines.append(line)

        return '\n'.join(translated_lines)


    def base64_zip_encode(self, s: str) -> str:
        return base64.b64encode(zlib.compress(s.encode('utf-8'))).decode('utf-8')


    def base64_zip_decode(self, s: str) -> str:
        return zlib.decompress(base64.b64decode(s.encode('utf-8'))).decode('utf-8')


    def freq_remap(self, s: str) -> str:
        freqs = collections.Counter(s).most_common()
        order = [f[0] for f in freqs]

        # Counter sort chars of same frequency by order of occurance
        # this automatically maitains stability for back and forth remapping

        remap = dict(zip(order, order[::-1]))
        return ''.join([remap[ch] for ch in s])


    def encode(self, s):
        if self.config['use-base64-encryption']:
            return self.freq_remap(self.base64_zip_encode(s)) + 'E'
        else:
            return s + '\n'


    def decode(self, s):
        if s[-1] == 'E':
            return self.base64_zip_decode(self.freq_remap(s[0:-1]))
        else:
            return s[0:-1]

    # exported functions, return type:
    #
    #     [bool]
    #     [bool, str]
    #
    #     if bool is True , str can be omitted
    #     if bool is False, str must be provided as error message
    #
    # catch any exception thrown and logs them if needed

    def export_createContent(self) -> str:
        try:
            try:
                today_file_content = self.repo_handler.get_contents(self.today_file_name())
            except github.UnknownObjectException:
                return [True, self.title()]
            return [True, self.decode(self.get_file_handler_content(today_file_content)).strip() + "\n\n\n" + self.title()]
        except Exception as e:
            self.log(traceback.format_exc())
            return [False, str(e)]


    def export_submitContent(self, content):
        self.log(content)
        try:
            blob = self.repo_handler.create_git_blob(self.encode(self.translate_content(content.strip())), "utf-8")
            element = github.InputGitTreeElement(path=self.today_file_name(), mode='100644', type='blob', sha=blob.sha)

            branch_sha = self.repo_handler.get_branch(self.repo_handler.default_branch).commit.sha
            base_tree = self.repo_handler.get_git_tree(sha=branch_sha)

            tree = self.repo_handler.create_git_tree([element], base_tree)
            parent = self.repo_handler.get_git_commit(sha=branch_sha)

            commit = self.repo_handler.create_git_commit('update from ' + socket.gethostname(), tree, [parent])
            self.repo_handler.get_git_ref('heads/' + self.repo_handler.default_branch).edit(commit.sha)
            return [True]
        except Exception as e:
            self.log(traceback.format_exc())
            return [False, str(e)]


    def export_viewText(self, regname) -> str:
        try:
            text_lines = []
            for name, content in self.pull_diaries(regname):
                text_lines.append('<---------------------------%s----------------------------\n\n\n' % name[0:-4])
                text_lines.append(content.rstrip())
                text_lines.append('\n\n\n');

            return [True, ''.join(text_lines[0:-1])]
        except Exception as e:
            self.log(traceback.format_exc())
            return [False, str(e)]


    def export_viewHtml(self, regname) -> str:
        try:
            html_lines = []
            html_lines.append('<!DOCTYPE html>')
            html_lines.append('<html>')
            html_lines.append('    <head>')
            html_lines.append('        <meta charset="utf-8"/>')
            html_lines.append('        <style>')
            html_lines.append('            .diaryDiv {')
            html_lines.append('                border: 2px outset red;')
            html_lines.append('                background-color: lightblue;')
            html_lines.append('            }')
            html_lines.append('            .diaryDiv pre {')
            html_lines.append('                white-space: pre-wrap;')
            html_lines.append('                word-wrap: break-word;')
            html_lines.append('            }')
            html_lines.append('            .diaryDiv img {')
            html_lines.append('                max-width: 100%;')
            html_lines.append('                height: auto;')
            html_lines.append('            }')
            html_lines.append('        </style>')
            html_lines.append('    </head>')
            html_lines.append('    <body>')

            pattern_imgbase64 = re.compile('^\s*\[\[imgbase64\s+?(\S+)\s*\]\]\s*$')
            pattern_timestamp = re.compile('^\s*(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}.\d{6} .* wrote:)\s*$')

            for name, content in self.pull_diaries(regname):
                last_empty = False
                last_timestamp = None

                has_content = False
                div_started = False

                for line in content.splitlines():
                    striped_line = line.rstrip()
                    matched_timestamp = pattern_timestamp.match(striped_line)

                    if matched_timestamp:
                        last_timestamp = matched_timestamp.group(1)

                    elif striped_line:
                        has_content = True
                        if not div_started:
                            html_lines.append('        <div class="diaryDiv">')
                            html_lines.append('            <h2 style="text-align:center; color:brown">%s</h2>' % name[:-4])
                            div_started = True

                        if last_timestamp:
                            html_lines.append('            <h3 style="color:blue;">%s</h3>' % last_timestamp)
                        elif last_empty:
                            html_lines.append('            <br/>')

                        # if there are both timestamp and empty line
                        # only prints timestamp

                        last_empty = False
                        last_timestamp = None

                        matched_imgbase64 = pattern_imgbase64.match(striped_line)
                        if matched_imgbase64:
                            # tag <img> is inline level
                            # means which doesn't start a new line, need an explicit <br/>
                            html_lines.append('            <img alt="image" src="%s"/><br/>' % matched_imgbase64.group(1))
                        else:
                            html_lines.append('            <pre>%s</pre>' % html.escape(striped_line))
                    else:
                        last_empty = True

                if has_content:
                    html_lines.append('        </div>')

            html_lines.append('    </body>')
            html_lines.append('</html>')
            return [True, '\n'.join(html_lines)]
        except Exception as e:
            self.log(traceback.format_exc())
            return [False, str(e)]
