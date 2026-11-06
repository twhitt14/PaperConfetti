#!/usr/bin/env python3
"""Check authored public API documentation in compiler-produced symbol graphs."""
import argparse
import json
import pathlib
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parents[1]

def review(graphs, source_root):
    """Ignore imported/synthesized symbols, never guess declarations with a regex."""
    symbols = {}
    for graph in graphs:
        for symbol in graph.get('symbols', []):
            location = symbol.get('location', {}).get('uri', '')
            path = pathlib.Path(urllib.parse.unquote(urllib.parse.urlparse(location).path))
            if not location or source_root not in path.parents:
                continue
            if symbol.get('accessLevel') not in ('public', 'open') or symbol.get('spi', False):
                continue
            symbols[symbol['identifier']['precise']] = symbol
    missing = []
    for symbol in symbols.values():
        lines = symbol.get('docComment', {}).get('lines', [])
        if not any(line.get('text', '').strip() for line in lines):
            missing.append('.'.join(symbol.get('pathComponents', [symbol['identifier']['precise']])))
    return {'publicSourceSymbols': len(symbols), 'undocumented': sorted(missing)}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('graphs', type=pathlib.Path)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    args = parser.parse_args()
    paths = sorted(args.graphs.glob('*.symbols.json'))
    if not paths:
        raise SystemExit('No compiler symbol graphs found; documentation coverage is unknown.')
    result = review([json.loads(p.read_text()) for p in paths], ROOT / 'Sources' / 'PaperConfetti')
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    if not result['publicSourceSymbols']:
        raise SystemExit('No authored public symbols found; refusing a vacuous documentation pass.')
    if result['undocumented']:
        raise SystemExit('Missing public documentation: ' + ', '.join(result['undocumented']))
    print(f"Documented {result['publicSourceSymbols']} authored public symbols.")

if __name__ == '__main__':
    main()
