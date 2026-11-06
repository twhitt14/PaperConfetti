import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('check_docs', ROOT / 'tools/check_docs.py')
docs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(docs)

class DocumentationTests(unittest.TestCase):
    def symbol(self, name, comment=None, location=True, access='public', spi=False):
        value = {'identifier': {'precise': name}, 'pathComponents': [name], 'accessLevel': access, 'spi': spi}
        if location:
            value['location'] = {'uri': (ROOT / 'Sources/PaperConfetti/Example.swift').as_uri()}
        if comment is not None:
            value['docComment'] = {'lines': [{'text': comment}]}
        return value

    def testMissingAndBlankAuthoredPublicCommentsFailCoverage(self):
        graph = {'symbols': [self.symbol('documented', 'A summary.'), self.symbol('missing'), self.symbol('blank', ' ')]}
        result = docs.review([graph], ROOT / 'Sources/PaperConfetti')
        self.assertEqual(result, {'publicSourceSymbols': 3, 'undocumented': ['blank', 'missing']})

    def testSynthesizedPrivateAndTestingSymbolsDoNotClaimPublicCoverage(self):
        graph = {'symbols': [self.symbol('synthesized', location=False), self.symbol('private', access='internal'),
                             self.symbol('spi', spi=True), self.symbol('real', 'A summary.')]}
        result = docs.review([graph, graph], ROOT / 'Sources/PaperConfetti')
        self.assertEqual(result, {'publicSourceSymbols': 1, 'undocumented': []})
