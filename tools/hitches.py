"""Fail-closed attribution of Xcode Animation Hitches to complete app signpost intervals.

Uses exported schema mnemonics, not column offsets. Raw nanosecond timestamps are
in the same trace clock. Missing export/markers never become a zero-hitch result.
"""
from pathlib import Path
import re
import xml.etree.ElementTree as ET


class EvidenceError(ValueError):
    pass


def table(path, schema, required):
    root = ET.parse(path).getroot()
    ids = {element.get('id'): element for element in root.iter() if element.get('id')}

    def resolve(element):
        seen = set()
        while element.get('ref'):
            ref = element.get('ref')
            if ref in seen or ref not in ids:
                raise EvidenceError('Unresolved or cyclic Instruments reference')
            seen.add(ref); element = ids[ref]
        return element

    def scalar(element):
        element = resolve(element)
        if element.tag == 'sentinel':
            return None
        if element.tag == 'process':
            pid = element.find('pid')
            if pid is None:
                raise EvidenceError('Process has no PID')
            return int(resolve(pid).text)
        return element.get('fmt') if element.tag in ('os-log-metadata',) else element.text

    found = False
    rows = []
    for node in root.iter('node'):
        definition = node.find('schema')
        if definition is None or definition.get('name') != schema:
            continue
        found = True
        fields = [c.findtext('mnemonic') for c in definition.findall('col')]
        if not required <= set(fields):
            raise EvidenceError(f'{schema} schema changed; inspect the trace manually')
        for row in node.findall('row'):
            if len(row) != len(fields):
                raise EvidenceError('Malformed Instruments row')
            rows.append(dict(zip(fields, map(scalar, row))))
    if not found:
        raise EvidenceError(f'{schema} table was not exported')
    return rows


def union_duration(intervals):
    end = None
    total = 0
    for a, b in sorted(intervals):
        if end is None or a >= end:
            total += b - a
        elif b > end:
            total += b - end
        end = b if end is None else max(end, b)
    return total


def attribute(markers_file, hitches_file, payload):
    pid = payload['process_id']
    expected = {(r['scenario'], r['round']) for r in payload['rows']}
    markers = table(markers_file, 'OSSignpostIntervals', {'start', 'duration', 'name', 'subsystem', 'process', 'end-process', 'start-message'})
    intervals = {}
    for row in markers:
        if row['name'] != 'Renderer study' or row['subsystem'] != 'org.paperconfetti.benchmarks' or row['process'] != pid:
            continue
        if row['end-process'] != pid:
            raise EvidenceError('Unmatched trial end process')
        match = re.fullmatch(r'([a-z0-9-]+) round=(\d+)', row['start-message'] or '')
        if not match:
            raise EvidenceError('Unexpected study signpost label')
        key = (match[1], int(match[2]))
        start, duration = int(row['start']), int(row['duration'])
        if duration <= 0 or key in intervals:
            raise EvidenceError('Duplicate or incomplete trial interval')
        intervals[key] = (start, start + duration)
    if set(intervals) != expected or len(payload['rows']) != len(expected):
        raise EvidenceError('Incomplete or mismatched trial markers; no hitch comparison available')
    ordered = sorted(intervals.values())
    if any(a[1] > b[0] for a, b in zip(ordered, ordered[1:])):
        raise EvidenceError('Study trial intervals overlap')
    for row in payload['rows']:
        start, end = intervals[(row['scenario'], row['round'])]
        if abs((end - start) / 1e9 - row['duration_s']) > 0.15:
            raise EvidenceError('Trace/app interval duration mismatch')
    hitches = table(hitches_file, 'hitches', {'start', 'duration', 'process', 'is-system', 'display', 'swap-id'})
    events = set()
    for row in hitches:
        if row['is-system'] not in ('0', '1'):
            raise EvidenceError('Unknown hitch attribution')
        if row['is-system'] == '1':
            continue
        if row['process'] is None:
            raise EvidenceError('Non-system hitch has no process attribution')
        if row['process'] != pid:
            continue
        start, duration = int(row['start']), int(row['duration'])
        if duration <= 0:
            raise EvidenceError('Invalid hitch duration')
        events.add((start, start + duration, row['display'], row['swap-id']))
    result = []
    for key, (start, end) in intervals.items():
        hits = [(max(a, start), min(b, end)) for a, b, _, _ in events if a < end and b > start]
        launch_end = min(end, start + 500_000_000)
        launch = [(a, min(b, launch_end)) for a, b in hits if a < launch_end]
        flight = [(max(a, launch_end), b) for a, b in hits if b > launch_end]
        result.append({'scenario': key[0], 'round': key[1], 'hitch_count': len(hits),
                       'hitch_ms': union_duration(hits) / 1e6,
                       'max_hitch_ms': max((b-a for a,b in hits), default=0) / 1e6,
                       'launch_hitch_ms': union_duration(launch) / 1e6,
                       'flight_hitch_ms': union_duration(flight) / 1e6,
                       'trial_duration_s': (end-start) / 1e9})
    return result


def from_exports(output, trace, payload):
    if payload.get('simulator'):
        return {'status': 'unavailable', 'reason': 'Simulator timing is not physical frame-delivery evidence.'}
    try:
        files = {entry['schema']: Path(output) / entry['file'] for entry in trace.get('exports', []) if 'file' in entry}
        rows = attribute(files['OSSignpostIntervals'], files['hitches'], payload)
        return {'status': 'available', 'rows': rows,
                'definition': 'Process-attributed Animation Hitches intervals, clipped to each trial; overlapping duration is unioned. Launch is first 500ms. This is not Apple animation-active hitch time ratio.'}
    except (KeyError, OSError, ValueError, TypeError, ET.ParseError) as error:
        return {'status': 'unavailable', 'reason': str(error) or 'Required trace export missing; inspect Instruments.'}
