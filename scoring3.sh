#!/usr/bin/env bash
# scoring3.sh - 실습3 (네임스페이스 / 값·참조·포인터 매개변수 / 동적할당) 자동채점, 20점 만점
#
# 사용법: bash scoring3.sh [check_name|all]
#   check_name 을 주면 해당 항목만 채점하고 통과 시 exit 0, 실패 시 exit 1
#   (GitHub Classroom Run Command 용)
#   생략하거나 all 이면 전체 채점표와 총점을 출력 (항상 exit 0)
#
# 요구사항: python3, g++
# 학생 저장소 루트에서 실행. 클래스1의 이름/네임스페이스/헤더는 자동 탐지.
#
# check 목록 (배점)
#   namespace_check(1) using_header_check(1) class1_prefix_check(1)
#   class1_postfix_check(1) class1_compound_check(1)
#   parVal_check(1) parRef_check(1) parPtr_check(1)
#   retVal_check(1) retRef_check(1) retPtr_check(1)
#   compile_check(2) par_functions_check(2) ret_functions_check(2)
#   dynamic_variable_check(3)

if ! command -v python3 >/dev/null 2>&1; then
  echo "[ERROR] python3 not found" >&2
  exit 2
fi

python3 - "$@" <<'PYEOF'
# -*- coding: utf-8 -*-
import os
import re
import subprocess
import sys
import tempfile

try:
    sys.stdout.reconfigure(encoding='utf-8')
except Exception:
    pass

CHECK_ARG = sys.argv[1] if len(sys.argv) > 1 else 'all'

# ---------------------------------------------------------------- 설정
STRICT_NS_NAME = False        # True: 네임스페이스 이름이 '영문+숫자(학번)' 형식이어야 통과
REQUIRE_FUNC_IN_NS = True     # True: par*/ret* 함수가 본인 네임스페이스 안에 정의되어야 통과
NS_PATTERN = re.compile(r'^[A-Za-z_]+[0-9]+$')
SKIP_DIRS = {'.git', '.github', '.vscode', 'build', 'out', 'bin', 'node_modules'}
MAX_DEPTH = 3

NO_CLASS = '클래스1(헤더에 정의된 클래스)을 찾지 못함'
NO_MAIN = 'main 함수가 있는 cpp 파일을 찾지 못함'


# ---------------------------------------------------------------- 파일 읽기
def read_text(path):
    with open(path, 'rb') as f:
        data = f.read()
    for enc in ('utf-8', 'cp949'):
        try:
            return data.decode(enc)
        except UnicodeDecodeError:
            pass
    return data.decode('utf-8', errors='replace')


_TOKEN = re.compile(
    r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\\n])*"|\'(?:\\.|[^\'\\\n])*\'', re.S)
_LIT = re.compile(r'"(?:\\.|[^"\\\n])*"|\'(?:\\.|[^\'\\\n])*\'')


def strip_comments(s):
    def rep(m):
        t = m.group(0)
        if t.startswith('//'):
            return ' '
        if t.startswith('/*'):
            return ' ' + '\n' * t.count('\n')
        return t
    return _TOKEN.sub(rep, s)


def mask_literals(s):
    return _LIT.sub(lambda m: m.group(0)[0] + ' ' * (len(m.group(0)) - 2) + m.group(0)[-1], s)


def find_files(exts):
    out = []
    for root, dirs, files in os.walk('.'):
        depth = 0 if root == '.' else root.count(os.sep)
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and depth < MAX_DEPTH]
        for f in sorted(files):
            if f.lower().endswith(exts):
                out.append(os.path.normpath(os.path.join(root, f)))
    return sorted(out)


CPPS = find_files(('.cpp', '.cc', '.cxx'))
HDRS_ALL = find_files(('.h', '.hpp', '.hh'))
NC = {p: strip_comments(read_text(p)) for p in CPPS + HDRS_ALL}   # 주석 제거
SRC = {p: mask_literals(NC[p]) for p in NC}                       # + 문자열 내용 제거


# ---------------------------------------------------------------- 중괄호 도우미
def match_brace(s, i):
    """s[i] == '{' 일 때 짝이 되는 '}' 다음 인덱스 (없으면 -1)"""
    depth = 0
    for j in range(i, len(s)):
        c = s[j]
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return j + 1
    return -1


_QUAL = re.compile(r'\s*(?:(?:const|noexcept|override)\b\s*)*\{')


def find_defs(text, sig):
    """sig 정규식 뒤에 함수 본문 { } 이 오는 경우(=정의)만 [(match, body)] 로 반환"""
    out = []
    for m in re.finditer(sig, text):
        q = _QUAL.match(text, m.end())
        if not q:
            continue
        end = match_brace(text, q.end() - 1)
        if end < 0:
            continue
        out.append((m, text[q.end():end - 1]))
    return out


# ---------------------------------------------------------------- 자동 탐지
MAIN = None
for _p in CPPS:
    if os.path.basename(_p).lower() == 'main.cpp' and re.search(r'\bint\s+main\s*\(', SRC[_p]):
        MAIN = _p
        break
if MAIN is None:
    for _p in CPPS:
        if re.search(r'\bint\s+main\s*\(', SRC[_p]):
            MAIN = _p
            break
MAIN_SRC = SRC[MAIN] if MAIN else ''


def resolve_headers():
    by_base = {}
    for h in HDRS_ALL:
        by_base.setdefault(os.path.basename(h).lower(), []).append(h)
    found, seen = [], set()
    queue = [MAIN] if MAIN else []
    while queue:
        cur = queue.pop()
        for inc in re.findall(r'#\s*include\s*"([^"]+)"', NC[cur]):
            for h in by_base.get(os.path.basename(inc).lower(), []):
                if h not in seen:
                    seen.add(h)
                    found.append(h)
                    queue.append(h)
    return found or HDRS_ALL


HEADERS = resolve_headers()
if MAIN:
    IMPL = [p for p in CPPS if p != MAIN and os.path.dirname(p) == os.path.dirname(MAIN)]
else:
    IMPL = list(CPPS)
CLS_SRC = '\n'.join(SRC[p] for p in HEADERS + IMPL)

CLASS_DEF = re.compile(r'\b(?:class|struct)\s+(\w+)\s*(?:final\s*)?(?::[^{;]*)?\{')


def detect_class():
    cands = {}
    for p in HEADERS:
        t = SRC[p]
        for m in CLASS_DEF.finditer(t):
            if re.search(r'\benum\s*$', t[:m.start()]):
                continue
            end = match_brace(t, m.end() - 1)
            body = t[m.end():end - 1] if end > 0 else ''
            cands.setdefault(m.group(1), body)
    if not cands:
        return None
    names = list(cands)
    used = [c for c in names if re.search(r'\b' + re.escape(c) + r'\b', MAIN_SRC)] or names

    def has_ops(c):
        return bool(re.search(r'operator\s*(?:\+\+|\+=)', cands[c]) or
                    re.search(r'\b' + re.escape(c) + r'\s*::\s*operator\s*(?:\+\+|\+=)', CLS_SRC))
    for c in used:
        if has_ops(c):
            return c
    return used[0]


def detect_ns(cls):
    if not cls:
        return None
    for p in HEADERS:
        t = SRC[p]
        for m in re.finditer(r'\bnamespace\s+(\w+)\s*\{', t):
            if m.group(1) == 'std':
                continue
            end = match_brace(t, m.end() - 1)
            if end < 0:
                continue
            if re.search(r'\b(?:class|struct)\s+' + re.escape(cls) + r'\b', t[m.end():end]):
                return m.group(1)
    return None


CLS = detect_class()
NS = detect_ns(CLS)


def C():
    """클래스 이름 (네임스페이스 한정 허용)"""
    return r'(?:\w+::)*' + re.escape(CLS)


def QUAL():
    """클래스 밖 정의 시 'Class::' 접두 (선택)"""
    return r'(?:(?:\w+::)*' + re.escape(CLS) + r'\s*::\s*)?'


# ---------------------------------------------------------------- 클래스/헤더 체크
def namespace_check():
    if not CLS:
        return False, NO_CLASS
    if not NS:
        return False, '클래스가 (std 가 아닌) 네임스페이스 안에 정의되어 있지 않음'
    if STRICT_NS_NAME and not NS_PATTERN.match(NS):
        return False, '네임스페이스 이름(%s)이 이름+학번 형식이 아님' % NS
    return True, 'namespace %s' % NS


def using_header_check():
    if not HEADERS:
        return False, '헤더 파일이 없음'
    bad = [h for h in HEADERS if re.search(r'\busing\s+namespace\b', SRC[h])]
    if bad:
        return False, '헤더에 using 지시자 사용: ' + ', '.join(bad)
    return True, ''


def class1_prefix_check():
    if not CLS:
        return False, NO_CLASS
    sig = r'(?<!\w)' + C() + r'\s*&\s*' + QUAL() + r'operator\s*\+\+\s*\(\s*(?:void)?\s*\)'
    ds = find_defs(CLS_SRC, sig)
    if not ds:
        return False, '참조를 리턴하는 전위증가연산자 operator++() 정의를 찾지 못함'
    for _, body in ds:
        if re.search(r'\bthis\b', body):
            return True, ''
    return False, '전위증가연산자에서 this 를 사용하지 않음'


def class1_postfix_check():
    if not CLS:
        return False, NO_CLASS
    sig = (r'(?<!\w)(?:const\s+)?' + C() + r'\s+' + QUAL() +
           r'operator\s*\+\+\s*\(\s*int\s*\w*\s*\)')
    ds = find_defs(CLS_SRC, sig)
    if not ds:
        return False, '후위증가연산자 operator++(int) 정의를 찾지 못함'
    for _, body in ds:
        if re.search(r'\bthis\b', body):
            return True, ''
    return False, '후위증가연산자에서 this 를 사용하지 않음'


def class1_compound_check():
    if not CLS:
        return False, NO_CLASS
    sig = r'(?<!\w)(?:void|' + C() + r'\s*&?)\s*' + QUAL() + r'operator\s*\+=\s*\([^)]*\)'
    ds = find_defs(CLS_SRC, sig)
    if not ds:
        return False, '복합할당연산자 operator+= 정의를 찾지 못함'
    for _, body in ds:
        if re.search(r'\bthis\b', body):
            return True, ''
    return False, '복합할당연산자에서 this 를 사용하지 않음'


# ---------------------------------------------------------------- par*/ret* 함수 체크
def func_check(fn, ptype, ret):
    if not CLS:
        return False, NO_CLASS
    if not MAIN:
        return False, NO_MAIN
    c = C()
    if ptype == 'val':
        P = r'(?:const\s+)?' + c + r'\s+(\w+)'
    elif ptype == 'ref':
        P = c + r'\s*&\s*(\w+)'
    else:
        P = c + r'\s*\*\s*(\w+)'
    if ret == 'void':
        RT = r'\bvoid\s+' + fn
    elif ret == 'val':
        RT = r'(?<![\w&*])' + c + r'\s+' + fn
    elif ret == 'ref':
        RT = r'(?<!\w)' + c + r'\s*&\s*' + fn
    else:
        RT = r'(?<!\w)' + c + r'\s*\*\s*' + fn
    sig = RT + r'\s*\(\s*' + P + r'\s*\)'

    scope = MAIN_SRC
    if NS and REQUIRE_FUNC_IN_NS:
        blocks = [b for _, b in find_defs(MAIN_SRC, r'\bnamespace\s+' + re.escape(NS) + r'\b')]
        scope = '\n'.join(blocks)

    ds = find_defs(scope, sig)
    if not ds:
        if find_defs(MAIN_SRC, sig):
            return False, '%s 함수가 네임스페이스 %s 밖에 정의됨' % (fn, NS)
        return False, '%s 함수 정의(반환형/매개변수 형태)를 찾지 못함' % fn

    last = ''
    for m, body in ds:
        p = re.escape(m.group(1))
        if ptype == 'ptr':
            use = (r'\(\s*\*\s*' + p + r'\s*\)\s*\+=|\*\s*' + p + r'\s*\+=|\b' + p +
                   r'\s*->\s*operator\s*\+=')
        else:
            use = r'\b' + p + r'\s*\+=|\b' + p + r'\s*\.\s*operator\s*\+='
        if not re.search(use, body):
            last = '매개변수에 복합할당연산자 += 를 사용하지 않음'
            continue
        if ret == 'void':
            if re.search(r'\breturn\s*[^;\s]', body):
                last = '리턴이 없어야 하는데 값을 리턴함'
                continue
        else:
            if not re.search(r'\breturn\b[^;]*\b' + p + r'\b[^;]*;', body):
                last = '매개변수를 리턴하지 않음'
                continue
        return True, ''
    return False, last


# ---------------------------------------------------------------- main 체크
def main_body():
    ds = find_defs(MAIN_SRC, r'\bint\s+main\s*\([^)]*\)')
    return ds[0][1] if ds else None


def pr(v):
    return r'<<\s*\(?\s*' + re.escape(v) + r'\b(?!\s*[.\[(])'


def prp(v):
    return r'<<\s*\(?\s*\*\s*' + re.escape(v) + r'\b(?!\s*[.\[(])'


def run_seq(B, start, steps):
    pos = start
    for label, rx in steps:
        m = re.search(rx, B[pos:], re.S)
        if not m:
            return False, '%s 를(을) 찾지 못함(또는 순서가 다름)' % label
        pos += m.end()
    return True, ''


def find_names(B):
    c = C()
    o = re.search(r'(?<![\w&*])(?:const\s+)?' + c + r'\s+(\w+)\s*(?:\(|\{|=|;)', B)
    if not o:
        return None, '클래스1 객체 선언을 찾지 못함'
    obj = o.group(1)
    o_esc = re.escape(obj)
    r = re.search(c + r'\s*&\s*(\w+)\s*(?:=|\{|\()\s*' + o_esc + r'\b', B)
    if not r:
        return None, '객체를 참조하는 참조객체 선언을 찾지 못함'
    p = re.search(c + r'\s*\*\s*(\w+)\s*(?:=|\{|\()\s*&\s*' + o_esc + r'\b', B)
    if not p:
        return None, '객체를 가리키는 포인터변수 선언을 찾지 못함'
    return (obj, r.group(1), p.group(1), o.end()), ''


def _prepare_main():
    if not CLS:
        return None, NO_CLASS
    if not MAIN:
        return None, NO_MAIN
    B = main_body()
    if B is None:
        return None, 'main 함수 본문을 찾지 못함'
    return B, ''


def par_functions_check():
    B, err = _prepare_main()
    if B is None:
        return False, err
    names, err = find_names(B)
    if not names:
        return False, err
    obj, ref, ptr, start = names
    c = C()
    steps = [
        ('객체 출력', pr(obj)),
        ('parVal(객체) 호출', r'\bparVal\s*\(\s*' + re.escape(obj) + r'\s*\)'),
        ('parVal 후 객체 출력', pr(obj)),
        ('참조객체 선언', c + r'\s*&\s*' + re.escape(ref) + r'\s*(?:=|\{|\()\s*' + re.escape(obj) + r'\b'),
        ('참조객체 출력', pr(ref)),
        ('parRef(참조객체) 호출', r'\bparRef\s*\(\s*' + re.escape(ref) + r'\s*\)'),
        ('parRef 후 참조객체 출력', pr(ref)),
        ('포인터변수 선언', c + r'\s*\*\s*' + re.escape(ptr) + r'\s*(?:=|\{|\()\s*&\s*' + re.escape(obj) + r'\b'),
        ('포인터가 가리키는 값 출력', prp(ptr)),
        ('parPtr(포인터변수) 호출', r'\bparPtr\s*\(\s*' + re.escape(ptr) + r'\s*\)'),
        ('parPtr 후 포인터가 가리키는 값 출력', prp(ptr)),
    ]
    return run_seq(B, start, steps)


def ret_functions_check():
    B, err = _prepare_main()
    if B is None:
        return False, err
    names, err = find_names(B)
    if not names:
        return False, err
    obj, ref, ptr, start = names
    steps = [
        ('생성자를 명시적으로 호출해 객체에 값 대입',
         r'\b' + re.escape(obj) + r'\s*=\s*(?:\w+::)*' + re.escape(CLS) + r'\s*[({]'),
        ('객체 출력', pr(obj)),
        ('retVal(객체) 리턴값 출력', r'<<[^;]*\bretVal\s*\(\s*' + re.escape(obj) + r'\s*\)'),
        ('참조객체 출력', pr(ref)),
        ('retRef(참조객체) 리턴값 출력', r'<<[^;]*\bretRef\s*\(\s*' + re.escape(ref) + r'\s*\)'),
        ('포인터가 가리키는 값 출력', prp(ptr)),
        ('retPtr(포인터변수) 리턴값이 가리키는 값 출력',
         r'<<[^;]*\*[^;]*\bretPtr\s*\(\s*' + re.escape(ptr) + r'\s*\)'),
    ]
    return run_seq(B, start, steps)


import re

def dynamic_variable_check():
    B, err = _prepare_main()
    if B is None:
        return False, err
    
    cls_pattern = re.escape(CLS)
    
    # = new 뿐만 아니라 {new ...} 형태 및 대소문자 무시(?i) 지원
    new_pattern = (
        r'(?:[\w:]+\s*\*?\s+|\b)([\w_]+)\s*(?:=\s*|\{\s*)new\s+(?:\w+::)*' 
        + cls_pattern + r'(?:\(\)||\b)'
    )
    
    m = re.search(new_pattern, B, re.IGNORECASE)
    if not m:
        return False, '클래스1 동적할당(new) 을 찾지 못함'
    
    v = m.group(1)
    p = re.escape(v)
    
    steps = [
        ('set 함수로 값 설정',
         r'\b' + p + r'\s*->\s*(?i:set)\w*\s*\(|\(\s*\*\s*' + p + r'\s*\)\s*\.\s*(?i:set)\w*\s*\('),
        ('동적변수가 가리키는 값 출력', prp(v)),
        ('delete 로 메모리 해제', r'\bdelete\s+(?:\[\s*\]\s*)?' + p + r'\b'),
    ]
    
    return run_seq(B, m.end(), steps)


# ---------------------------------------------------------------- 컴파일
def compile_check():
    if not MAIN:
        return False, NO_MAIN
    d = os.path.dirname(MAIN)
    srcs = [p for p in CPPS if os.path.dirname(p) == d]
    incs = sorted({os.path.dirname(h) or '.' for h in HDRS_ALL} | {d or '.'})
    exe = os.path.join(tempfile.gettempdir(), 'scoring3_prog')
    cmd = ['g++', '-std=c++17', '-o', exe] + ['-I' + i for i in incs] + srcs
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    except FileNotFoundError:
        return False, 'g++ 를 찾을 수 없음'
    except subprocess.TimeoutExpired:
        return False, '컴파일 시간 초과'
    if r.returncode != 0:
        lines = [l for l in (r.stderr or '').strip().splitlines() if l.strip()][:5]
        return False, '컴파일 오류: ' + ' | '.join(lines)
    return True, ''


# ---------------------------------------------------------------- 채점표
CHECKS = [
    ('namespace_check', 1, namespace_check),
    ('using_header_check', 1, using_header_check),
    ('class1_prefix_check', 1, class1_prefix_check),
    ('class1_postfix_check', 1, class1_postfix_check),
    ('class1_compound_check', 1, class1_compound_check),
    ('parVal_check', 1, lambda: func_check('parVal', 'val', 'void')),
    ('parRef_check', 1, lambda: func_check('parRef', 'ref', 'void')),
    ('parPtr_check', 1, lambda: func_check('parPtr', 'ptr', 'void')),
    ('retVal_check', 1, lambda: func_check('retVal', 'val', 'val')),
    ('retRef_check', 1, lambda: func_check('retRef', 'ref', 'ref')),
    ('retPtr_check', 1, lambda: func_check('retPtr', 'ptr', 'ptr')),
    ('compile_check', 2, compile_check),
    ('par_functions_check', 2, par_functions_check),
    ('ret_functions_check', 2, ret_functions_check),
    ('dynamic_variable_check', 3, dynamic_variable_check),
]
ALIASES = {'class1_compound_chech': 'class1_compound_check'}
assert sum(p for _, p, _ in CHECKS) == 20


def run_one(name, pts, fn):
    try:
        ok, msg = fn()
    except Exception as e:  # 채점 스크립트 자체 오류는 실패 처리
        ok, msg = False, '채점 중 오류: %r' % (e,)
    got = pts if ok else 0
    tag = 'PASS' if ok else 'FAIL'
    line = '[%s] %s (%d/%d)' % (tag, name, got, pts)
    if msg:
        line += ' - ' + msg
    print(line)
    return ok, got


print('[info] main=%s, headers=%s, class=%s, namespace=%s' %
      (MAIN, ','.join(HEADERS) or None, CLS, NS))

target = ALIASES.get(CHECK_ARG, CHECK_ARG)
if target == 'all':
    total = 0
    for name, pts, fn in CHECKS:
        total += run_one(name, pts, fn)[1]
    print('TOTAL: %d/20' % total)
    sys.exit(0)

for name, pts, fn in CHECKS:
    if name == target:
        ok, _ = run_one(name, pts, fn)
        sys.exit(0 if ok else 1)

print('[ERROR] unknown check: %s' % CHECK_ARG, file=sys.stderr)
print('available: ' + ', '.join(n for n, _, _ in CHECKS) + ', all', file=sys.stderr)
sys.exit(2)
PYEOF
exit $?
