#!/usr/bin/env python3
"""Validate configuration metadata in both host app and WidgetKit extension."""
import json
import pathlib
import sys

app = pathlib.Path(sys.argv[1])
if (app / 'Contents').is_dir():
    extension = app / 'Contents/PlugIns/AgendaWidgetMac.appex'
    relative = pathlib.Path('Contents/Resources/Metadata.appintents/extract.actionsdata')
else:
    extension = app / 'PlugIns/AgendaWidgetiOS.appex'
    relative = pathlib.Path('Metadata.appintents/extract.actionsdata')
required = {'allCalendars', 'calendars', 'showTasks', 'showAllDay', 'showMonth'}
for bundle in (app, extension):
    path = bundle / relative
    if not path.is_file():
        raise SystemExit(f'Missing App Intents metadata: {path}')
    metadata = json.loads(path.read_text())
    action = metadata.get('actions', {}).get('AgendaConfiguration')
    if not action:
        raise SystemExit(f'Missing AgendaConfiguration: {bundle}')
    parameters = {parameter['name'] for parameter in action['parameters']}
    if not required.issubset(parameters):
        raise SystemExit(f'Missing configuration parameters: {bundle}')
    print(f'PASS: {bundle.name} exposes AgendaConfiguration and all widget options')
