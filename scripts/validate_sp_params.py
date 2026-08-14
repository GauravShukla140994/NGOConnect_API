#!/usr/bin/env python3
"""
NGOConnect -- Full Stack Parameter Validator
==============================================
Phase 1-3  (existing):
  SP IN params declared in setup SQL  ↔  DAL AddParameter / AddWithValue calls

Phase 4  (new):
  SP SELECT output columns / aliases  ↔  DAL Col<T>(r, "ColumnName") mapper reads
  Catches: DAL reads a column the SP never SELECTs (always-null bug),
           SP aliases never read by the DAL mapper (silently dropped data).

Phase 5  (new):
  TypeScript API inline request types  ↔  C# request model properties
  Catches: field sent by TS but missing from C# model (ignored on server),
           field in C# model missing from TS type (never sent from mobile).

Phase 6  (new):
  Mobile screen API call object literals  ↔  TypeScript type definitions
  Catches: screen sends a field not declared in the API function's type,
           API type declares a field the screen never actually sends.

Usage:
    python scripts/validate_sp_params.py

Exit code:
    0  = all clear
    1  = mismatches found (blocks deployment)
"""

import re
import sys
from pathlib import Path

# ── Paths ──────────────────────────────────────────────────────────────────────
ROOT            = Path(__file__).parent.parent
SETUP_SQL       = ROOT / "Documents" / "NGOConnect_Complete_Setup_v5.0.sql"
DAL_DIR         = ROOT / "NGOConnect.Infrastructure" / "DAL"
MODELS_DIR      = ROOT / "NGOConnect.Core" / "Models"
CONTROLLERS_DIR = ROOT / "NGOConnect.API" / "Controllers"
APP_SRC         = ROOT.parent / "App" / "NGOConnectApp" / "src"
API_DIR         = APP_SRC / "api"
SCREENS_DIR     = APP_SRC / "screens"

# ── Known Phase-4 false positives ────────────────────────────────────────────
# These are validator parser limitations, not real bugs.  Document each one
# so re-runs stay clean without requiring a full parser rewrite.
#
# Format:  (dal_file, sp_name, direction, col_name)
#   direction = 'dal_reads'  → validator says DAL reads col not in SP
#   direction = 'sp_has'     → validator says SP has col not read by DAL
#
_KNOWN_FP: set[tuple[str, str, str, str]] = {
    # FP1 — Validator scans Col<> reads sequentially; Org_ListRecommended's
    #        inline mapper (MatchScore, VerificationStatusCode) sits between the
    #        Org_List call site and MapOrgListItem (line 551) which does NOT read
    #        these columns.  MapOrgListItem is the actual Org_List mapper.
    ('OrgDal.cs', 'Org_List', 'dal_reads', 'MatchScore'),
    ('OrgDal.cs', 'Org_List', 'dal_reads', 'VerificationStatusCode'),

    # FP2 — ActiveCount is a derived-table alias inside Org_GetDonors used in
    #        a JOIN condition (rd_agg.ActiveCount) then expressed as IsRecurring
    #        in the top-level SELECT.  It is never a top-level output column.
    ('OrgDal.cs', 'Org_GetDonors', 'sp_has', 'ActiveCount'),

    # FP3 — User_GetProfile SP body ends cleanly with END //.  The validator's
    #        SP-body regex over-runs into the immediately following
    #        'CREATE PROCEDURE User_GetImpact' declaration.
    ('UserDal.cs', 'User_GetProfile', 'sp_has', 'User_GetImpact'),

    # FP4 — attended / total are derived-table aliases inside a subquery used
    #        to compute ReliabilityPct in Org_GetVolunteerProfile and
    #        Org_GetMemberImpact.  They are never top-level output columns.
    ('OrgDal.cs', 'Org_GetVolunteerProfile', 'sp_has', 'attended'),
    ('OrgDal.cs', 'Org_GetVolunteerProfile', 'sp_has', 'total'),
    # AvgRating IS returned by the SP (IFNULL subquery with alias AvgRating).
    # The validator's parser loses track of it inside the complex nested expr.
    ('OrgDal.cs', 'Org_GetVolunteerProfile', 'dal_reads', 'AvgRating'),
    # ComplaintCount and JoinedAt ARE in the SP; parser confuses them after the
    # nested subquery block.  Both are correctly read by the DAL mapper.
    ('OrgDal.cs', 'Org_GetVolunteerProfile', 'sp_has', 'ComplaintCount'),
    ('OrgDal.cs', 'Org_GetVolunteerProfile', 'sp_has', 'JoinedAt'),
    ('OrgDal.cs', 'Org_GetVolunteerProfile', 'sp_has', 'RequestedAt'),

    # FP5 — Same derived-table alias issue as FP4 for Org_GetMemberImpact.
    ('OrgDal.cs', 'Org_GetMemberImpact', 'sp_has', 'attended'),
    ('OrgDal.cs', 'Org_GetMemberImpact', 'sp_has', 'total'),

    # FP6 — Org_GetDashboard: SQL comment "treated as not expired" contains "as not",
    #        which the AS-alias regex picks up as a phantom alias. Not a real column.
    ('OrgDal.cs', 'Org_GetDashboard', 'sp_has', 'not'),
}

# SQL keywords that appear in SELECT clauses but are not column names
_SQL_KW = {
    'null', 'distinct', 'all', 'top', 'limit', 'case', 'when', 'then',
    'else', 'end', 'true', 'false', 'from', 'where', 'join', 'on',
    'and', 'or', 'not', 'in', 'is', 'as', 'by', 'asc', 'desc',
    'coalesce', 'ifnull', 'if', 'count', 'sum', 'avg', 'max', 'min',
    'left', 'right', 'inner', 'outer', 'group', 'order', 'having',
    'select', 'insert', 'update', 'delete', 'set', 'into', 'values',
    'exists', 'between', 'like', 'concat', 'length', 'date', 'now',
    'curdate', 'timestampdiff', 'year', 'month', 'day', 'hour', 'minute',
    'second', 'interval', 'datediff', 'str_to_date', 'date_format',
    'substring', 'trim', 'upper', 'lower', 'replace', 'round', 'cast',
    'convert', 'unsigned', 'signed', 'char', 'decimal', 'varchar',
}


# ─────────────────────────────────────────────────────────────────────────────
# Utility helpers
# ─────────────────────────────────────────────────────────────────────────────

def _strip_cs_comments(text):
    text = re.sub(r'//[^\n]*', '', text)
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
    return text


def _strip_sql_comments(text):
    return re.sub(r'--[^\n]*', '', text)


def _strip_ts_comments(text):
    text = re.sub(r'//[^\n]*', '', text)
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
    return text


def _pascal_to_camel(name):
    return name[0].lower() + name[1:] if name else name


def _extract_braced_block(text, start):
    """
    Find the opening '{' at or after `start`, then return everything up to
    and including the matching '}'. Returns (inner_content, end_pos).
    """
    brace = text.find('{', start)
    if brace == -1:
        return None, -1
    depth = 0
    i = brace
    while i < len(text):
        if text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
            if depth == 0:
                return text[brace + 1:i], i + 1
        i += 1
    return None, -1


_KEY_KW = {
    'string', 'number', 'boolean', 'object', 'any', 'null', 'undefined',
    'never', 'void', 'unknown', 'true', 'false', 'http', 'https',
    'await', 'return', 'const', 'let', 'var', 'new', 'typeof', 'instanceof',
}


def _extract_obj_keys(inner_text):
    """
    Extract property keys from an object literal body string.

    Handles:
      - Explicit:   "orgName: form.orgName.trim()"  → "orgName"
      - Shorthand:  "{ memberId: x, roleCode }"     → "roleCode"

    Skips spreads (...obj), computed properties ([key]: val), and
    ignores VALUE tokens that appear after `:` in key: value pairs.

    Strategy: split by commas at depth-0, then inspect each slot.
    """
    slots = []
    current = []
    depth = 0
    for ch in inner_text:
        if ch in '({[':
            depth += 1
            current.append(ch)
        elif ch in ')}]':
            depth -= 1
            current.append(ch)
        elif ch == ',' and depth == 0:
            slots.append(''.join(current).strip())
            current = []
        else:
            current.append(ch)
    if current:
        slots.append(''.join(current).strip())

    keys = []
    for slot in slots:
        slot = slot.strip()
        if not slot or slot.startswith('...') or slot.startswith('//'):
            continue
        # Explicit key: starts with  identifier  followed by ':'  (not ::)
        m = re.match(r'^([a-zA-Z_]\w*)\s*(?:\?)?:', slot)
        if m:
            k = m.group(1)
            if k not in _KEY_KW:
                keys.append(k)
        elif re.match(r'^[a-z_][a-zA-Z_0-9]*$', slot):
            # Pure identifier with no colon = shorthand property
            if slot not in _KEY_KW:
                keys.append(slot)
        # else: computed [key], spread, or complex expression — skip

    return list(dict.fromkeys(keys))   # preserve order, deduplicate


# ─────────────────────────────────────────────────────────────────────────────
# Phase 1 -- SP IN-parameter declarations
# ─────────────────────────────────────────────────────────────────────────────

def parse_sp_params(sql_path):
    """{ "Sp_Name": ["p_param1", ...] }"""
    text = sql_path.read_text(encoding='utf-8', errors='ignore')
    pattern = re.compile(
        r'CREATE\s+PROCEDURE\s+(\w+)\s*\((.*?)\)\s*(?:\w+\s*:\s*)?(?:BEGIN|//)',
        re.IGNORECASE | re.DOTALL
    )
    sp_params = {}
    for m in pattern.finditer(text):
        sig  = m.group(2)
        sp_params[m.group(1).strip()] = [
            p.lower() for p in re.findall(r'\bIN\s+(p_\w+)', sig, re.IGNORECASE)
        ]
    return sp_params


# ─────────────────────────────────────────────────────────────────────────────
# Phase 1b -- SP bodies + SELECT column names
# ─────────────────────────────────────────────────────────────────────────────

def parse_sp_bodies(sql_path):
    """
    { "Sp_Name": (body_text, {lowercase_column_names}) }
    Column names are all AS-aliases plus bare identifiers in SELECT clauses.
    """
    text = sql_path.read_text(encoding='utf-8', errors='ignore')
    pattern = re.compile(
        r'CREATE\s+PROCEDURE\s+(\w+)\s*\(.*?\)\s*(?:\w+\s*:\s*)?BEGIN\s*(.*?)\s*END\s*//',
        re.IGNORECASE | re.DOTALL
    )
    result = {}
    for m in pattern.finditer(text):
        sp_name = m.group(1).strip()
        body    = m.group(2)
        clean   = _strip_sql_comments(body)

        # Collect all AS aliases -- most reliable output column indicator
        aliases = set(re.findall(r'\bAS\s+(\w+)\b', clean, re.IGNORECASE))

        # Also grab bare column names from the first SELECT...FROM block
        # Remove subquery content first
        flat = re.sub(r'\([^()]*\)', '(__sub__)', clean)
        sel  = re.search(r'\bSELECT\b(.*?)\bFROM\b', flat, re.IGNORECASE | re.DOTALL)
        bare = set()
        if sel:
            for item in sel.group(1).split(','):
                item = item.strip()
                words = [w for w in re.findall(r'\b([A-Za-z_]\w*)\b', item)
                         if w.lower() not in _SQL_KW]
                if words:
                    bare.add(words[-1])

        result[sp_name] = (body, {c.lower() for c in aliases | bare})
    return result


# ─────────────────────────────────────────────────────────────────────────────
# Phase 2 -- DAL AddParameter / AddWithValue calls
# ─────────────────────────────────────────────────────────────────────────────

def parse_dal_calls(dal_dir):
    """{ "File.cs": { "Sp_Name": ["p_param1", ...] } }"""
    results  = {}
    sp_re    = re.compile(r'"([A-Z][a-z][A-Za-z]*(?:_[A-Za-z0-9]+)+)"')  # Pascal-case only; excludes ALL_CAPS setting keys
    param_re = re.compile(
        r'AddParameter\s*\(\s*\w+\s*,\s*"(p_\w+)"|'
        r'\.(?:AddWithValue|Add)\s*\(\s*"(p_\w+)"',
        re.IGNORECASE
    )
    for cs_file in dal_dir.glob('**/*.cs'):
        text  = cs_file.read_text(encoding='utf-8', errors='ignore')
        lines = text.splitlines()
        file_key          = cs_file.name
        results[file_key] = {}
        current_sp        = None
        collected         = []

        for line in lines:
            s = line.lstrip()
            if s.startswith('//') or s.startswith('*') or s.startswith('/*'):
                continue
            m = sp_re.search(line)
            if m:
                c = m.group(1)
                if '_' in c and not c.startswith('p_'):
                    if current_sp:
                        results[file_key][current_sp] = collected
                    current_sp = c
                    collected  = []
            for pm in param_re.finditer(line):
                p = (pm.group(1) or pm.group(2) or '').lower()
                if p and p not in collected:
                    collected.append(p)

        if current_sp and collected:
            results[file_key][current_sp] = collected
    return results


# ─────────────────────────────────────────────────────────────────────────────
# Phase 2b -- DAL Col<T>(r, "ColumnName") mapper reads
# ─────────────────────────────────────────────────────────────────────────────

def parse_dal_col_reads(dal_dir):
    """
    { "File.cs": { "Sp_Name": ["Col1", "Col2", ...] } }

    Two-pass approach:
      Pass 1 -- find named mapper function bodies: { "MapProfile": ["UserId", ...] }
      Pass 2 -- link each Execute*Async("SpName", mapper) to its col reads.
    """
    # Matches both Col<T>(r, "Name") and ColNullable<T>(r, "Name")
    # findall returns (group1, group2) tuples — normalised by _col_match() below
    col_re       = re.compile(r'ColNullable<[^>]+>\s*\(\s*\w+\s*,\s*"(\w+)"|Col<[^>]+>\s*\(\s*\w+\s*,\s*"(\w+)"', re.IGNORECASE)

    def _col_matches(text):
        """Return flat list of column-name strings from col_re.findall()."""
        return [g1 or g2 for g1, g2 in col_re.findall(text)]
    mapper_re    = re.compile(
        r'(?:private|public|protected|internal)?\s*static\s+\S[\w<>?,\s]*?\s+(Map\w+)\s*\(',
        re.IGNORECASE
    )
    exec_re      = re.compile(
        r'Execute\w*Async\s*\(\s*"([A-Z][A-Za-z_0-9]+)"',
        re.IGNORECASE
    )
    named_map_re = re.compile(
        r'Execute\w+Async\s*\([^,]+,\s*(Map\w+)',
        re.IGNORECASE
    )
    # Matches start of an inline lambda mapper: "r => new Model" or "(r) => new Model"
    inline_lambda_re = re.compile(
        r'\b(?:r|row|reader)\s*(?:,\s*[a-z]\w*)?\s*\)?\s*=>\s*new\s+\w+',
        re.IGNORECASE
    )

    result = {}

    for cs_file in dal_dir.glob('**/*.cs'):
        text     = cs_file.read_text(encoding='utf-8', errors='ignore')
        clean    = _strip_cs_comments(text)
        file_key = cs_file.name
        result[file_key] = {}

        # -- Pass 1: named mapper function bodies -----------------------------
        named_mappers = {}   # { "MapProfile": ["UserId", "Mobile", ...] }
        for m in mapper_re.finditer(clean):
            func_name = m.group(1)
            tail  = clean[m.end():]
            arrow = tail.find('=>')
            brace = tail.find('{')
            if arrow != -1 and (brace == -1 or arrow < brace):
                body_start = m.end() + arrow + 2
            else:
                body_start = m.end() + (brace if brace != -1 else 0)
            inner, _ = _extract_braced_block(clean, body_start)
            if inner is not None:
                named_mappers[func_name] = _col_matches(inner)

        # -- Pass 2: link SP calls to col reads --------------------------------
        lines = clean.splitlines()
        for i, line in enumerate(lines):
            ex_m = exec_re.search(line)
            if not ex_m:
                continue
            sp_name = ex_m.group(1)
            if '_' not in sp_name:
                continue
            if 'Dynamic' in line:
                continue   # DynamicRow SPs -- SP shape is the ground truth
            if 'ExecuteWriteAsync' in line:
                continue   # Write SPs return IsSuccess/Message via WriteResult, no Col<T> mapper

            # Look ahead up to 200 lines to find the mapper (named or inline)
            lookahead = '\n'.join(lines[i:i + 200])

            # Check for named mapper reference first
            nm_m = named_map_re.search(lookahead[:500])
            if nm_m and nm_m.group(1) in named_mappers:
                cols = named_mappers[nm_m.group(1)]
            else:
                # Inline lambda: find "r => new Model {" and extract only
                # the brace-counted block so we don't bleed into adjacent mappers
                il_m = inline_lambda_re.search(lookahead)
                if il_m:
                    inner, _ = _extract_braced_block(lookahead, il_m.start())
                    cols = _col_matches(inner) if inner else []
                else:
                    cols = []

            if cols:
                existing = result[file_key].setdefault(sp_name, [])
                for c in cols:
                    if c not in existing:
                        existing.append(c)

    return result


# ─────────────────────────────────────────────────────────────────────────────
# Phase 3 -- Validate SP IN params vs DAL
# ─────────────────────────────────────────────────────────────────────────────

def validate_sp_in_params(sp_params, dal_calls):
    issues = []
    for dal_file, sp_map in dal_calls.items():
        for sp_name, dal_passed in sp_map.items():
            if sp_name not in sp_params:
                continue
            declared = set(sp_params[sp_name])
            passed   = set(dal_passed)
            miss = declared - passed
            xtra = passed   - declared
            if miss or xtra:
                issues.append('')
                issues.append(f'  [{dal_file}] -> {sp_name}')
                if miss:
                    issues.append(f'    MISSING in DAL  : {sorted(miss)}')
                if xtra:
                    issues.append(f'    EXTRA in DAL    : {sorted(xtra)}')
    return issues


# ─────────────────────────────────────────────────────────────────────────────
# Phase 4 -- Validate SP SELECT output vs DAL Col<T> mapper reads
# ─────────────────────────────────────────────────────────────────────────────

def validate_col_reads(sp_bodies, dal_col_reads):
    """
    For each typed SP call in the DAL:
      (a) DAL reads col X but X is absent from the SP body  -> always-null bug
      (b) SP declares AS-alias Y but mapper never reads it  -> silently dropped data
    """
    # Columns returned by WRITE SPs (IsSuccess/Message/entity IDs) --
    # these are consumed by WriteResult, not a typed mapper.
    _write_cols = {
        'issuccess', 'message', 'orgid', 'userid', 'projectid',
        'communitypostid', 'postid', 'polloptionid', 'donationcampaignid',
        'transactionid', 'recurringdonationid', 'sosincidentid',
        'sessionid', 'applicationid', 'badgeid', 'totalcount',
    }

    issues = []
    for dal_file, sp_map in dal_col_reads.items():
        for sp_name, dal_cols in sp_map.items():
            if sp_name not in sp_bodies:
                continue
            sp_body, sp_output_cols = sp_bodies[sp_name]
            sp_body_lower = sp_body.lower()

            # (a) DAL reads columns not found anywhere in the SP body
            ghost = [
                c for c in dal_cols
                if c.lower() not in sp_body_lower
                and (dal_file, sp_name, 'dal_reads', c) not in _KNOWN_FP
            ]

            # (b) SP AS-aliases the mapper never reads
            sp_aliases = set(re.findall(r'\bAS\s+(\w+)\b', sp_body, re.IGNORECASE))
            dal_lower  = {c.lower() for c in dal_cols}
            dropped    = sorted(
                a for a in sp_aliases
                if a.lower() not in dal_lower
                and a.lower() not in _write_cols
                and (dal_file, sp_name, 'sp_has', a) not in _KNOWN_FP
            )

            if ghost or dropped:
                issues.append('')
                issues.append(f'  [{dal_file}] -> {sp_name}')
                if ghost:
                    issues.append(f'    DAL reads col not in SP (always null) : {ghost}')
                if dropped:
                    issues.append(f'    SP alias not read by mapper (data loss): {dropped}')
    return issues


# ─────────────────────────────────────────────────────────────────────────────
# Phase 5 -- TypeScript inline request types vs C# request model properties
# ─────────────────────────────────────────────────────────────────────────────

def parse_controller_route_models(controllers_dir):
    """
    { "PUT /org/{}/resubmit": "ResubmitOrgRequest", ... }
    """
    if not controllers_dir.exists():
        return {}

    http_re   = re.compile(
        r'\[Http(Post|Put|Get|Delete|Patch)(?:\s*\(\s*"([^"]*?)"\s*\))?\]',
        re.IGNORECASE
    )
    route_re  = re.compile(r'\[Route\s*\(\s*"([^"]*?)"\s*\)\]', re.IGNORECASE)
    body_re   = re.compile(r'\[FromBody\]\s+(\w+)\s+\w+', re.IGNORECASE)

    result = {}

    for cs_file in controllers_dir.glob('**/*.cs'):
        text  = _strip_cs_comments(cs_file.read_text(encoding='utf-8', errors='ignore'))
        lines = text.splitlines()

        # Locate controller-level [Route("api/v1/org")]
        base = ''
        for line in lines:
            rm = route_re.search(line)
            if rm:
                base = rm.group(1).strip('/')
                base = re.sub(r'^api/v\d+/', '', base, flags=re.IGNORECASE)
                break

        pending = []
        for line in lines:
            hm = http_re.search(line)
            if hm:
                method    = hm.group(1).upper()
                sub_route = hm.group(2) or ''
                # Normalize route params: {orgId:int} -> {}
                sub_route = re.sub(r'\{[^}]+\}', '{}', sub_route)
                full_route = '/' + base + ('/' + sub_route if sub_route else '')
                full_route = re.sub(r'/+', '/', full_route).rstrip('/')
                pending.append((method, full_route))
                continue

            bm = body_re.search(line)
            if bm and pending:
                for method, route in pending:
                    result[f'{method} {route}'] = bm.group(1)
                pending = []

    return result


def parse_cs_model_properties(models_dir):
    """{ "RegisterOrgRequest": ["OrgName", "RegistrationNumber", ...] }"""
    if not models_dir.exists():
        return {}

    prop_re  = re.compile(
        r'public\s+[\w<>\[\]?]+\s+(\w+)\s*\{\s*get\s*;\s*(?:set\s*;)?\s*\}',
        re.IGNORECASE
    )
    class_re = re.compile(r'^\s*public\s+class\s+(\w+)', re.IGNORECASE | re.MULTILINE)

    result = {}
    for cs_file in models_dir.glob('**/*.cs'):
        text  = _strip_cs_comments(cs_file.read_text(encoding='utf-8', errors='ignore'))
        lines = text.splitlines()

        current_class = None
        brace_depth   = 0
        class_depth   = None

        for line in lines:
            cm = class_re.search(line)
            if cm:
                current_class = cm.group(1)
                class_depth   = brace_depth + line.count('{') - line.count('}')
                result.setdefault(current_class, [])

            brace_depth += line.count('{') - line.count('}')

            if current_class and class_depth is not None:
                if brace_depth < class_depth:
                    current_class = None
                    class_depth   = None
                else:
                    pm = prop_re.search(line)
                    if pm and pm.group(1) not in result.get(current_class, []):
                        result[current_class].append(pm.group(1))

    return result


def parse_ts_api_functions(api_dir):
    """
    Parses *.api.ts files for functions with explicit inline data: { ... } types.

    Returns:
      { "orgApi.resubmit": { "url": "/org/{}/resubmit", "method": "PUT",
                             "ts_fields": ["orgName", "is80GEligible", ...] } }
    """
    if not api_dir.exists():
        return {}

    url_re = re.compile(
        r'apiClient\.(post|put|get|delete|patch)\s*(?:<[^>]*>)?\s*\(\s*[`\'"]([^`\'"]+)[`\'"]',
        re.IGNORECASE
    )
    _ts_kw = {'string', 'number', 'boolean', 'object', 'any', 'null', 'undefined',
               'never', 'void', 'unknown'}

    result = {}

    for ts_file in sorted(api_dir.glob('*.api.ts')):
        api_obj = ts_file.stem.replace('.api', '') + 'Api'
        text    = ts_file.read_text(encoding='utf-8', errors='ignore')
        clean   = _strip_ts_comments(text)

        # Split by top-level function entries inside the api object literal
        func_start_re = re.compile(r'^\s{2}(\w+)\s*:', re.MULTILINE)
        spans = [(m.group(1), m.start()) for m in func_start_re.finditer(clean)]
        spans.append(('__end__', len(clean)))

        for idx, (func_name, fstart) in enumerate(spans[:-1]):
            fend    = spans[idx + 1][1]
            segment = clean[fstart:fend]

            # Only handle functions with an inline data: { ... } type block
            dtm = re.search(r'\bdata\s*:\s*\{', segment)
            if not dtm:
                continue

            inner, _ = _extract_braced_block(segment, dtm.start())
            if inner is None:
                continue

            # Extract field names with optionality: word + optional ? + colon
            # e.g. "orgName: string" -> required, "adminNotes?: string" -> optional
            all_matches   = re.findall(r'\b(\w+)(\?)?:', inner)
            ts_required   = [f for f, opt in all_matches if not opt and f not in _ts_kw]
            ts_optional   = [f for f, opt in all_matches if opt and f not in _ts_kw]
            ts_fields     = ts_required + ts_optional
            if not ts_fields:
                continue

            # Extract HTTP method + URL
            um = url_re.search(segment)
            if um:
                method   = um.group(1).upper()
                raw_url  = um.group(2)
                norm_url = re.sub(r'\$\{[^}]+\}', '{}', raw_url).split('?')[0]
                norm_url = '/' + norm_url.lstrip('/')
            else:
                method, norm_url = 'UNKNOWN', '/unknown'

            result[f'{api_obj}.{func_name}'] = {
                'url':       norm_url,
                'method':    method,
                'ts_fields': ts_fields,       # all fields
                'ts_required': ts_required,   # only non-optional fields
            }

    return result


def validate_ts_vs_cs(ts_api_funcs, controller_models, cs_models):
    """Match each TS inline-type function to its C# request model and compare."""
    issues = []

    for key, info in ts_api_funcs.items():
        route_key  = f'{info["method"]} {info["url"]}'
        model_name = controller_models.get(route_key) or controller_models.get(route_key.rstrip('/'))
        if not model_name or model_name not in cs_models:
            continue

        cs_camel  = {_pascal_to_camel(p): p for p in cs_models[model_name]}
        ts_set    = set(info['ts_fields'])

        extra_in_ts   = [f for f in info['ts_fields'] if f not in cs_camel]
        missing_in_ts = [_pascal_to_camel(p) for p in cs_models[model_name]
                         if _pascal_to_camel(p) not in ts_set]

        if extra_in_ts or missing_in_ts:
            issues.append('')
            issues.append(f'  {key}  <->  {model_name}  ({route_key})')
            if extra_in_ts:
                issues.append(f'    In TypeScript but NOT in C# model (server ignores): {extra_in_ts}')
            if missing_in_ts:
                issues.append(f'    In C# model but NOT in TypeScript type (never sent): {missing_in_ts}')

    return issues


# ─────────────────────────────────────────────────────────────────────────────
# Phase 6 -- Screen API call object literals vs TypeScript type definitions
# ─────────────────────────────────────────────────────────────────────────────

def parse_screen_api_calls(screens_dir, ts_api_funcs):
    """
    For each function in ts_api_funcs, scan screen files for calls and extract
    the object literal keys actually sent.

    Returns:
      { "orgApi.resubmit": { "CreateOrgScreen.tsx": ["orgName", "is80GEligible", ...] } }
    """
    if not screens_dir.exists():
        return {}

    result = {}

    for key in ts_api_funcs:
        api_obj, func = key.split('.', 1)

        # Pattern: orgApi.resubmit( or just resubmit(
        call_res = [
            re.compile(rf'\b{re.escape(api_obj)}\.{re.escape(func)}\s*\('),
            re.compile(rf'(?<!\w\.){re.escape(func)}\s*\('),
        ]

        for tsx_file in screens_dir.glob('**/*.tsx'):
            text  = tsx_file.read_text(encoding='utf-8', errors='ignore')
            clean = _strip_ts_comments(text)

            for call_re in call_res:
                for cm in call_re.finditer(clean):
                    segment  = clean[cm.end():cm.end() + 2500]
                    brace_p  = segment.find('{')
                    paren_p  = segment.find(')')
                    if brace_p == -1 or (paren_p != -1 and paren_p < brace_p):
                        continue

                    inner, _ = _extract_braced_block(segment, brace_p)
                    if not inner:
                        continue

                    keys = _extract_obj_keys(inner)
                    if keys:
                        entry = result.setdefault(key, {})
                        screen = tsx_file.name
                        bucket = entry.setdefault(screen, [])
                        for k in keys:
                            if k not in bucket:
                                bucket.append(k)

    return result


def validate_screen_vs_ts_types(ts_api_funcs, screen_calls):
    """
    Compare object literal keys sent from screens vs TypeScript type definition.
    - Extra keys   : screen sends a key not declared in the TS type (always flagged)
    - Missing keys : REQUIRED TS fields never sent by the screen (optional fields skipped)
    """
    issues = []
    for key, screen_files in screen_calls.items():
        if key not in ts_api_funcs:
            continue
        info         = ts_api_funcs[key]
        ts_all       = set(info['ts_fields'])
        ts_required  = set(info.get('ts_required', info['ts_fields']))

        for screen_file, sent_keys in screen_files.items():
            sent_set = set(sent_keys)
            # Screen sends a field that is not in the TS type at all
            extra   = sorted(sent_set - ts_all)
            # Required TS field the screen never sends → will always be undefined/default
            missing = sorted(ts_required - sent_set)

            if extra or missing:
                issues.append('')
                issues.append(f'  {key}  <-  {screen_file}')
                if extra:
                    issues.append(f'    Screen sends key NOT in TypeScript type (type gap)  : {extra}')
                if missing:
                    issues.append(f'    Required TS field never sent by screen (always null) : {missing}')

    return issues


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

def main():
    sep    = '=' * 66
    subsep = '-' * 66
    all_ok = True

    print(sep)
    print('  NGOConnect Full Stack Parameter Validator')
    print(sep)

    if not SETUP_SQL.exists():
        print(f'[ERROR] Setup SQL not found: {SETUP_SQL}')
        return 1
    if not DAL_DIR.exists():
        print(f'[ERROR] DAL dir not found: {DAL_DIR}')
        return 1

    app_available = APP_SRC.exists()
    if not app_available:
        print(f'[WARN]  App source not found at {APP_SRC} -- Phases 5 & 6 will be skipped.')

    # ====================================================================
    # PHASES 1-3: SP IN params <-> DAL AddParameter
    # ====================================================================
    print(f'\n{subsep}')
    print('  PHASES 1-3  SP IN params  <->  DAL AddParameter calls')
    print(subsep)

    print('\n[1/6] Parsing SP IN-param declarations ...')
    sp_params = parse_sp_params(SETUP_SQL)
    print(f'      {len(sp_params)} stored procedures found.')

    print('\n[2/6] Scanning DAL AddParameter / AddWithValue calls ...')
    dal_calls   = parse_dal_calls(DAL_DIR)
    total_sites = sum(len(v) for v in dal_calls.values())
    print(f'      {len(dal_calls)} DAL files, {total_sites} SP call sites.')

    print('\n[3/6] Cross-referencing IN params ...')
    p3_issues = validate_sp_in_params(sp_params, dal_calls)
    if p3_issues:
        all_ok = False
        n = sum(1 for i in p3_issues if i.lstrip().startswith('['))
        print(f'  [FAIL] {n} SP(s) with IN-param mismatches:')
        for line in p3_issues:
            print(line)
    else:
        print('  [OK]   All SP IN-params match their DAL callers.')

    # ====================================================================
    # PHASE 4: SP SELECT output <-> DAL Col<T> mapper reads
    # ====================================================================
    print(f'\n{subsep}')
    print('  PHASE 4  SP SELECT output  <->  DAL Col<T> mapper reads')
    print(subsep)

    print('\n[4/6] Parsing SP bodies + SELECT columns ...')
    sp_bodies = parse_sp_bodies(SETUP_SQL)
    print(f'      {len(sp_bodies)} SP bodies parsed.')

    dal_cols        = parse_dal_col_reads(DAL_DIR)
    total_mapper_sp = sum(len(v) for v in dal_cols.values())
    print(f'      Col<T> mapper reads found for {total_mapper_sp} typed SP call site(s).')

    p4_issues = validate_col_reads(sp_bodies, dal_cols)
    if p4_issues:
        all_ok = False
        n = sum(1 for i in p4_issues if i.lstrip().startswith('['))
        print(f'\n  [FAIL] {n} SP(s) with SELECT <-> mapper mismatches:')
        for line in p4_issues:
            print(line)
    else:
        print('\n  [OK]   SP SELECT outputs match DAL mapper Col<T> reads.')

    # ====================================================================
    # PHASE 5: TypeScript inline types <-> C# request models
    # ====================================================================
    print(f'\n{subsep}')
    print('  PHASE 5  TypeScript inline request types  <->  C# request models')
    print(subsep)

    ts_api_funcs = {}
    if not app_available or not API_DIR.exists():
        print('\n  [SKIP] App source not found.')
    else:
        print('\n[5/6] Parsing TS inline request type definitions ...')
        ts_api_funcs = parse_ts_api_functions(API_DIR)
        print(f'      {len(ts_api_funcs)} function(s) with explicit inline types found.')

        print('      Parsing controller route -> C# model mappings ...')
        ctrl_models = parse_controller_route_models(CONTROLLERS_DIR)
        print(f'      {len(ctrl_models)} endpoint -> model mapping(s).')

        print('      Parsing C# model class properties ...')
        cs_models = parse_cs_model_properties(MODELS_DIR)
        print(f'      {len(cs_models)} model class(es).')

        p5_issues = validate_ts_vs_cs(ts_api_funcs, ctrl_models, cs_models)
        if p5_issues:
            all_ok = False
            n = sum(1 for i in p5_issues if '<->' in i)
            print(f'\n  [FAIL] {n} function(s) with TS type <-> C# model mismatches:')
            for line in p5_issues:
                print(line)
        else:
            print('\n  [OK]   TypeScript inline types align with C# request models.')

    # ====================================================================
    # PHASE 6: Screen API call fields <-> TypeScript type definitions
    # ====================================================================
    print(f'\n{subsep}')
    print('  PHASE 6  Screen API call fields  <->  TypeScript type definitions')
    print(subsep)

    if not app_available or not SCREENS_DIR.exists():
        print('\n  [SKIP] App source not found.')
    else:
        if not ts_api_funcs and API_DIR.exists():
            ts_api_funcs = parse_ts_api_functions(API_DIR)

        print(f'\n[6/6] Scanning screen files for API object literal keys ...')
        screen_calls    = parse_screen_api_calls(SCREENS_DIR, ts_api_funcs)
        total_screened  = sum(len(v) for v in screen_calls.values())
        print(f'      {total_screened} call site(s) matched to inline-typed functions.')

        p6_issues = validate_screen_vs_ts_types(ts_api_funcs, screen_calls)
        if p6_issues:
            all_ok = False
            n = sum(1 for i in p6_issues if '<-' in i and '<->' not in i)
            print(f'\n  [FAIL] {n} API call(s) with screen <-> TypeScript type mismatches:')
            for line in p6_issues:
                print(line)
        else:
            print('\n  [OK]   Screen API call fields match TypeScript type definitions.')

    # ── Summary ────────────────────────────────────────────────────────────────
    print(f'\n{sep}')
    if all_ok:
        print('  RESULT: ALL PHASES PASSED -- safe to deploy.')
    else:
        print('  RESULT: MISMATCHES FOUND -- fix before deploying.')
    print(sep)

    return 0 if all_ok else 1


if __name__ == '__main__':
    sys.exit(main())
