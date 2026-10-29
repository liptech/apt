#!/usr/bin/env python3
"""Build signed-by-Release DEP-11 catalogs. Input is presentation metadata only."""
import copy
import gzip
import pathlib
import subprocess
import sys
import xml.etree.ElementTree as ET

root = pathlib.Path(__file__).resolve().parents[1]
out = pathlib.Path(sys.argv[1])
suite = sys.argv[2]
components = sys.argv[3].split()
architectures = sys.argv[4].split()
for component in components:
    for architecture in architectures:
        sources = sorted(set((root / 'site/appstream/components' / component / architecture).glob('*.xml')) |
                         set((root / 'site/appstream/components' / component / 'all').glob('*.xml')))
        if not sources:
            continue
        catalog = ET.Element('components', {'version': '1.0', 'origin': 'liptech-' + suite})
        seen = set()
        for source in sources:
            subprocess.run(['appstreamcli', 'validate', '--no-net', str(source)], check=True)
            app = copy.deepcopy(ET.parse(source).getroot())
            identity = app.findtext('id')
            if not identity or identity in seen:
                raise SystemExit('Component missing ID or duplicated: ' + str(source))
            seen.add(identity)
            # Stock icons are not installed yet when previewing a local package.
            if identity == 'org.liptech.LikeAD':
                for icon in app.findall('icon'):
                    app.remove(icon)
                image = app.find('screenshots/screenshot/image')
                icon_url = image.text.split('/screenshots/')[0] + '/icon-128.png'
                ET.SubElement(app, 'icon', {'type': 'remote', 'width': '128', 'height': '128'}).text = icon_url
            catalog.append(app)
        target = out / 'dists' / suite / component / 'dep11'
        target.mkdir(parents=True, exist_ok=True)
        xml = target / ('Components-' + architecture + '.xml')
        ET.indent(catalog, space='  ')
        ET.ElementTree(catalog).write(xml, encoding='utf-8', xml_declaration=True)
        subprocess.run(['appstreamcli', 'validate', '--no-net', str(xml)], check=True)
        yaml = target / ('Components-' + architecture + '.yml')
        subprocess.run(['appstreamcli', 'convert', '--format=yaml', str(xml), str(yaml)], check=True)
        for source in (xml, yaml):
            with source.with_suffix(source.suffix + '.gz').open('wb') as stream:
                with gzip.GzipFile(filename='', mode='wb', fileobj=stream, mtime=0) as compressed:
                    compressed.write(source.read_bytes())
        print('AppStream:', yaml.relative_to(out), len(seen), 'component(s)')
