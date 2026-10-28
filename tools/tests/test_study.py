import copy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import compare as study
import hitches


class StudyTests(unittest.TestCase):
    def test_factor_pairs_change_only_the_intended_property(self):
        cases = {c['id']:c for c in study.manifest()}
        base = cases['layers-720']
        for case, field in [('size-7','size'),('texture-1x','textureScale'),('texture-2x','textureScale'),
                            ('texture-4x','textureScale'),('padded-textures','paddedTexture'),('samples-24','samples'),('samples-12','samples'),('no-tumble','tumble'),
                            ('no-flutter','flutter'),('still-host','hostMotion'),('uniform-speed','uniformSpeed'),
                            ('cold-textures','prewarm'),('opaque-proxy','opaqueProxy'),('adaptive-keyframes','sampling')]:
            changed = {k for k in base if base[k]!=cases[case][k]} - {'id','suites'}
            self.assertEqual(changed,{field})
        # Compare classic to the uniform-speed festive case, not the old mixed workload.
        changed = {k for k in base if cases['classic-matched'][k]!=cases['uniform-speed'][k]} - {'id','suites'}
        self.assertEqual(changed,{'shapes'})
        changed = {k for k in base if cases['trilinear-textures'][k]!=cases['padded-textures'][k]} - {'id','suites'}
        self.assertEqual(changed,{'trilinear'})

    def test_native_3d_pair_changes_only_shared_tilt(self):
        cases = {c['id']: c for c in study.manifest()}
        for count in (180, 720):
            flat, tilted = cases[f'emitter-{count}'], cases[f'emitter-3d-{count}']
            self.assertTrue(tilted['native3D'])
            self.assertEqual({k: v for k, v in tilted.items() if k not in ('id', 'native3D')},
                             {k: v for k, v in flat.items() if k != 'id'})

    def test_matrix_has_matched_renderer_counts_and_is_bounded(self):
        cases = study.manifest()
        for count in (180,720):
            rows = [c for c in cases if 'renderers' in c['suites'] and c['count']==count]
            self.assertEqual({c['renderer'] for c in rows},{'paper','layers','emitter','sprite'})
            self.assertTrue(all(c['size']==10 and c['shapes']=='festive' and c['hostMotion'] for c in rows))
        self.assertEqual(len([c for c in cases if c['id'].startswith('shape-')]),16)
        self.assertTrue(all(c['count']<=(5760 if 'stress' in c['suites'] else 720) and c['count']%5==0 and 12<=c['samples']<=48 for c in cases))

    def test_stress_suite_matches_loads_and_is_explicit(self):
        cases = study.select_cases('stress')
        self.assertEqual(len(cases), 24)
        self.assertEqual({c['count'] for c in cases}, {720, 1440, 2880, 5760})
        for count in (720, 1440, 2880, 5760):
            rows = [c for c in cases if c['count'] == count]
            self.assertEqual(len(rows), 6)
            self.assertEqual({(c['renderer'], c.get('native3D', False), c['atlas']) for c in rows},
                             {('emitter', False, False), ('emitter', True, False),
                              ('sprite', False, False), ('sprite', True, False),
                              ('sprite', False, True), ('sprite', True, True)})
            self.assertTrue(all(c['hostMotion'] and c['shapes'] == 'festive' and c['size'] == 10 for c in rows))
        self.assertFalse(any('stress' in c['suites'] for c in study.select_cases('all')))

    def test_cold_case_is_alone_in_a_fresh_process(self):
        groups=study.chunks(study.select_cases('all'))
        self.assertTrue(all(len(g)<=4 for g in groups))
        self.assertEqual([g[0]['id'] for g in groups if not g[0]['prewarm']],['cold-textures'])
        self.assertTrue(all(len(g)==1 for g in groups if not g[0]['prewarm']))
        with self.assertRaises(study.p.ProfileError): study.select_cases('renderers','paper-720,paper-720')
        with self.assertRaises(study.p.ProfileError): study.select_cases('renderers','missing')

    def payload(self):
        return {'schema':2,'run_id':'r','pass':'timing','finished':True,'success':True,'simulator':False,'process_id':42,
                'rows':[{'scenario':'layers-720','round':0,'duration_s':5.5,'cpu_ms':20,'footprint_end_bytes':1000,
                         'requested_particles':720,'idle_after_settle':True,'callback_count':100,'warmup':True}]}

    def test_validation_rejects_noop_missing_invalid_and_wrong_device(self):
        cases=study.select_cases('renderers','layers-720')
        data=self.payload(); study.validate(data,'r','timing',cases,1,False)
        for key,value in [('requested_particles',0),('idle_after_settle',False),('callback_count',0),('cpu_ms',float('nan')),('duration_s',1),('footprint_end_bytes',0)]:
            bad=copy.deepcopy(data);bad['rows'][0][key]=value
            with self.subTest(key=key),self.assertRaises(study.p.ProfileError): study.validate(bad,'r','timing',cases,1,False)
        for key,value in [('success',False),('schema',1),('simulator',True),('run_id','old')]:
            bad=copy.deepcopy(data);bad[key]=value
            with self.assertRaises(study.p.ProfileError): study.validate(bad,'r','timing',cases,1,False)
        bad=copy.deepcopy(data);bad['rows']*=2
        with self.assertRaises(study.p.ProfileError): study.validate(bad,'r','timing',cases,1,False)

    def test_native_requires_a_finite_staged_start_receipt(self):
        cases=study.select_cases('renderers','emitter-3d-720')
        data=self.payload(); row=data['rows'][0]
        row.update(scenario='emitter-3d-720', native_staged_clock=True, native_arm_delay_ms=70)
        study.validate(data,'r','timing',cases,1,False)
        for key,value in [('native_staged_clock',False),('native_arm_delay_ms',None),
                          ('native_arm_delay_ms',float('nan')),('native_arm_delay_ms',0)]:
            bad=copy.deepcopy(data);bad['rows'][0][key]=value
            with self.assertRaises(study.p.ProfileError): study.validate(bad,'r','timing',cases,1,False)

    def test_sprite_requires_population_and_scene_update_evidence(self):
        cases=study.select_cases('renderers','sprite-3d-720')
        data=self.payload(); row=data['rows'][0]
        row.update(scenario='sprite-3d-720', sprite_particles_started=720, sprite_scene_updates=200)
        study.validate(data,'r','timing',cases,1,False)
        for key,value in [('sprite_particles_started',0),('sprite_particles_started',719),('sprite_scene_updates',0)]:
            bad=copy.deepcopy(data);bad['rows'][0][key]=value
            with self.assertRaises(study.p.ProfileError): study.validate(bad,'r','timing',cases,1,False)

    def test_report_keeps_missing_hitches_unavailable_and_excludes_warmup(self):
        data=self.payload();warm=copy.deepcopy(data['rows'][0]);warm.update(round=1,warmup=False,setup_ms=1,texture_prewarmed=True)
        data['rows'].append(warm)
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);receipt={'status':'<incomplete>','recordings':[]}
            study.write_report(root,receipt,[data])
            self.assertEqual(receipt['summary'][0]['samples'],1)
            self.assertIsNone(receipt['summary'][0]['hitch_ms'])
            self.assertIn('&lt;incomplete&gt;', (root/'report.html').read_text())


class HitchTests(unittest.TestCase):
    def xml(self, schema, fields, rows):
        cols=''.join(f'<col><mnemonic>{f}</mnemonic></col>' for f in fields)
        return f'<trace-query-result><node><schema name="{schema}">{cols}</schema>{rows}</node></trace-query-result>'

    def fixtures(self, root):
        marker_fields=['start','duration','name','subsystem','process','end-process','start-message']
        row='<row><start-time>1000000000</start-time><duration>5500000000</duration><signpost-name>Renderer study</signpost-name><subsystem>org.paperconfetti.benchmarks</subsystem><process id="p"><pid>42</pid></process><process ref="p"/><os-log-metadata fmt="layers-720 round=0"/></row>'
        markers=root/'markers.xml';markers.write_text(self.xml('OSSignpostIntervals',marker_fields,row))
        hitch_fields=['start','duration','process','is-system','display','swap-id']
        # Two overlapping launch hitches; third crosses trial end. Different PID/system hitches excluded.
        rows=''
        for i,(start,length,pid,system) in enumerate([(1100000000,20000000,42,0),(1110000000,20000000,42,0),
                                                   (6490000000,30000000,42,0),(2000000000,999000000,99,0),(3000000000,999000000,42,1)]):
            rows+=f'<row><start-time>{start}</start-time><duration>{length}</duration><process><pid>{pid}</pid></process><boolean>{system}</boolean><display-name>Display 1</display-name><uint32>{i}</uint32></row>'
        hits=root/'hits.xml';hits.write_text(self.xml('hitches',hitch_fields,rows))
        return markers,hits

    def test_references_filtering_overlap_clipping_and_launch_vs_flight(self):
        with tempfile.TemporaryDirectory() as d:
            markers,hits=self.fixtures(Path(d))
            rows=hitches.attribute(markers,hits,StudyTests().payload())
            self.assertEqual(len(rows),1);row=rows[0]
            self.assertEqual(row['hitch_count'],3)
            self.assertEqual(row['hitch_ms'],40)
            self.assertEqual(row['max_hitch_ms'],20)
            self.assertEqual(row['launch_hitch_ms'],30)
            self.assertEqual(row['flight_hitch_ms'],10)

    def test_empty_valid_table_is_zero_but_absent_evidence_is_not(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);markers,hits=self.fixtures(root)
            hits.write_text(self.xml('hitches',['start','duration','process','is-system','display','swap-id'],''))
            self.assertEqual(hitches.attribute(markers,hits,StudyTests().payload())[0]['hitch_ms'],0)
            result=hitches.from_exports(root,{},StudyTests().payload())
            self.assertEqual(result['status'],'unavailable');self.assertNotIn('rows',result)

    def test_incomplete_marker_schema_duration_or_process_never_becomes_zero(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)
            for before,after in [('5500000000','0'),('5500000000','5000000000'),('Renderer study','wrong'),('layers-720 round=0','layers-720 round=1'),('ref="p"','ref="missing"'),('<mnemonic>duration','<mnemonic>unknown')]:
                markers,hits=self.fixtures(root);markers.write_text(markers.read_text().replace(before,after))
                with self.subTest(before=before),self.assertRaises((hitches.EvidenceError,ValueError)):
                    hitches.attribute(markers,hits,StudyTests().payload())

    def test_unknown_hitch_process_cannot_silently_report_zero(self):
        with tempfile.TemporaryDirectory() as d:
            markers,hits=self.fixtures(Path(d))
            hits.write_text(hits.read_text().replace('<process><pid>42</pid></process>', '<sentinel/>'))
            with self.assertRaises(hitches.EvidenceError): hitches.attribute(markers,hits,StudyTests().payload())

    def test_duplicate_markers_and_trials_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            markers,hits=self.fixtures(Path(d));s=markers.read_text();row=s[s.index('<row>'):s.index('</row>')+6]
            markers.write_text(s.replace('</node>',row+'</node>'))
            with self.assertRaises(hitches.EvidenceError): hitches.attribute(markers,hits,StudyTests().payload())

if __name__=='__main__': unittest.main()
