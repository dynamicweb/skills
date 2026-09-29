#!/usr/bin/env python3
"""Generate the F&O half of a Truvio Commerce (powered by Dynamicweb) Integration Framework build from a spec.

READ-ONLY against F&O (it reads a $metadata file you already pulled) and against the database (sys.columns).
WRITES, only with --apply: the entity subset JSON (entities), the staging DDL file (sql), and the OData job
files (jobs) in the install's jobs folder. Without --apply every subcommand prints what it would write.

Owning reference: references/staging-pattern.md (stage 1 / stage 2 and the job files), references/order-flow.md
(the export jobs). Traps it encodes:
  - MCP create_integration_activity validates an OData source by calling the endpoint, so no OData activity can
    be created over MCP before the endpoint authenticates. The job file is written directly instead.
  - A job file is UTF-16LE with a BOM; any other encoding is not a job.
  - An empty <conditionals /> element makes the loader drop the whole table mapping without an error: it is
    never written.
  - Keys first, Edm types mapped as the provider maps them (String/Decimal/DateTimeOffset/Int32/Int64/Guid to
    System.String/Decimal/DateTime/Int32/Int64/Guid, F&O enums to System.Object); SQL-side schema blocks use the
    SqlColumn shape and are scoped to the one table or view the job touches.
  - Staging keys are nvarchar(50): a 9-column F&O key (WarehousesOnHandV2) must fit the 900-byte index limit.

Subcommands:
  entities --metadata <$metadata.xml> --sets A,B,C --out <entities.json>
  sql      --spec <spec.json> --entities <entities.json> --out <staging.sql>
  jobs     --spec <spec.json> --entities <entities.json> --jobs <wwwroot>/Files/Files/Integration/jobs
           [--sql-server <server> --database <db>]   (else $env:DW_SQL_CONNECTION "Server=...;Database=...")

The spec (see assets/templates/integration-spec.example.json):
  {"group": "<activity folder, no '&'>",
   "stage":  [{"job": "...", "entity": "<entity set>", "table": "<staging table>", "endpointId": 2, "cols": [...]}],
   "export": [{"job": "...", "entity": "<entity set>", "view": "<export view>", "endpointId": 13,
               "keys": [...], "cols": [...]}]}

Runtime: Python 3.12, standard library only; sqlcmd on PATH (Windows authentication) for the jobs subcommand.

Examples:
  python3 scripts/fo_job_files.py entities --metadata ./metadata.xml --sets ReleasedProductsV2,CustomersV3 --out ./fo-entities.json --apply
  python3 scripts/fo_job_files.py sql --spec ./spec.json --entities ./fo-entities.json --out ./01-staging.sql --apply
  python3 scripts/fo_job_files.py jobs --spec ./spec.json --entities ./fo-entities.json --jobs "<wwwroot>/Files/Files/Integration/jobs" --sql-server "<server>" --database "<db>"
"""
import argparse
import json
import os
import re
import subprocess
import sys
import uuid
from pathlib import Path
from xml.sax.saxutils import escape

DOTNET = {'Edm.String': 'System.String', 'Edm.Decimal': 'System.Decimal', 'Edm.DateTimeOffset': 'System.DateTime',
          'Edm.Int32': 'System.Int32', 'Edm.Int64': 'System.Int64', 'Edm.Guid': 'System.Guid',
          'Edm.Boolean': 'System.Boolean', 'Edm.Double': 'System.Double', 'Edm.Date': 'System.DateTime'}
SQLT = {'System.String': 'nvarchar(255)', 'System.Object': 'nvarchar(100)', 'System.Decimal': 'decimal(32,10)',
        'System.DateTime': 'datetime2(0)', 'System.Int32': 'int', 'System.Int64': 'bigint',
        'System.Guid': 'uniqueidentifier', 'System.Boolean': 'bit', 'System.Double': 'float'}
SQLDB = {'nvarchar': ('System.String', 'NVarChar'), 'nchar': ('System.String', 'NChar'),
         'decimal': ('System.Decimal', 'Decimal'), 'datetime2': ('System.DateTime', 'DateTime2'),
         'datetime': ('System.DateTime', 'DateTime'), 'int': ('System.Int32', 'Int'),
         'bigint': ('System.Int64', 'BigInt'), 'bit': ('System.Boolean', 'Bit'), 'float': ('System.Double', 'Float'),
         'uniqueidentifier': ('System.Guid', 'UniqueIdentifier')}


def fail(msg):
    print(f'ERROR {msg}', file=sys.stderr)
    sys.exit(1)


def load_json(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def net_type(edm):
    return DOTNET.get(edm, 'System.Object')


def check_columns(ent, spec):
    if spec['entity'] not in ent:
        fail(f"{spec['entity']} is not in the entities file: add it with the entities subcommand")
    props = {p['name'] for p in ent[spec['entity']]['properties']}
    missing = [c for c in spec['cols'] if c not in props]
    if missing:
        fail(f"{spec['entity']}: columns not in the environment's metadata: {missing}")


def keys_of(ent, spec):
    return spec.get('keys') or [k for k in ent[spec['entity']]['keys'] if k in spec['cols']]


def write_or_show(path, text, apply, encoding='utf-8'):
    if not apply:
        print(f'would write {path} ({len(text)} chars); pass --apply to write')
        return
    Path(path).write_text(text, encoding=encoding)
    print(f'wrote {path}')


# ------------------------------------------------------------------------------------------ entities
def cmd_entities(a):
    xml = Path(a.metadata).read_text(encoding='utf-8-sig')
    sets = dict(re.findall(r'<EntitySet Name="([^"]+)" EntityType="[^"]*\.([^".]+)"', xml))
    out = {}
    for es in [s.strip() for s in a.sets.split(',') if s.strip()]:
        if es not in sets:
            fail(f'entity set {es} is not in {a.metadata}')
        m = re.search(r'<EntityType Name="%s">(.*?)</EntityType>' % re.escape(sets[es]), xml, re.S)
        out[es] = {'entityType': sets[es],
                   'keys': re.findall(r'<PropertyRef Name="([^"]+)"', m.group(1)),
                   'properties': [{'name': n, 'type': t} for n, t in
                                  re.findall(r'<Property Name="([^"]+)" Type="([^"]+)"', m.group(1))]}
    write_or_show(a.out, json.dumps(out, indent=1), a.apply)


# ------------------------------------------------------------------------------------------ sql
def cmd_sql(a):
    spec, ent = load_json(a.spec), load_json(a.entities)
    out = ['-- Generated by fo_job_files.py sql. Idempotent: creates each staging table when missing.',
           '-- Column names are the F&O property names, so the stage-1 mappings are 1:1.', 'SET NOCOUNT ON;', '']
    for s in spec['stage']:
        check_columns(ent, s)
        types = {p['name']: net_type(p['type']) for p in ent[s['entity']]['properties']}
        keys = keys_of(ent, s)
        cols = []
        for c in s['cols']:
            t = SQLT[types[c]]
            if c in keys and t.startswith('nvarchar'):
                t = 'nvarchar(50)'
            elif 'Description' in c:
                t = 'nvarchar(max)'
            cols.append(f"    [{c}] {t} {'NOT NULL' if c in keys else 'NULL'}")
        cols.append(f"    [LoadedUtc] datetime2(0) NOT NULL CONSTRAINT [DF_{s['table']}_Loaded] DEFAULT sysutcdatetime()")
        cols.append(f"    CONSTRAINT [PK_{s['table']}] PRIMARY KEY ([" + '], ['.join(keys) + '])')
        out.append(f"IF OBJECT_ID(N'dbo.{s['table']}', N'U') IS NULL\nCREATE TABLE dbo.[{s['table']}] (\n"
                   + ',\n'.join(cols) + '\n);\nGO\n')
    write_or_show(a.out, '\n'.join(out), a.apply)


# ------------------------------------------------------------------------------------------ jobs
def odata_table(ent, entity, i='      '):
    e = ent[entity]
    order = e['keys'] + [p['name'] for p in e['properties'] if p['name'] not in e['keys']]
    types = {p['name']: net_type(p['type']) for p in e['properties']}
    cols = ''.join(
        f'{i}    <column type="Dynamicweb.DataIntegration.Integration.Column">\n'
        f'{i}      <name>{escape(c)}</name>\n{i}      <type>{types[c]}</type>\n'
        f'{i}      <isNew>False</isNew>\n{i}      <isPrimaryKey>{"True" if c in e["keys"] else "False"}</isPrimaryKey>\n'
        f'{i}    </column>\n' for c in order)
    return (f'\n{i}<table>\n{i}  <isNew>False</isNew>\n{i}  <tableName>{entity}</tableName>\n'
            f'{i}  <sqlSchema />\n{i}  <foreignKeys />\n{i}  <columns>\n{cols}{i}  </columns>\n{i}</table>\n    ')


def connection(a):
    server, db = a.sql_server, a.database
    if not (server and db):
        conn = os.environ.get('DW_SQL_CONNECTION', '')
        parts = dict(p.split('=', 1) for p in conn.split(';') if '=' in p)
        server = server or parts.get('Server') or parts.get('Data Source')
        db = db or parts.get('Database') or parts.get('Initial Catalog')
    if not (server and db):
        fail('no database: pass --sql-server and --database, or set DW_SQL_CONNECTION="Server=...;Database=..."')
    return server, db


def sql_columns(server, db, table):
    q = ("SET NOCOUNT ON; SELECT c.name, t.name, CASE WHEN t.name IN ('nvarchar','nchar') THEN "
         "CASE WHEN c.max_length = -1 THEN -1 ELSE c.max_length/2 END ELSE 0 END, "
         "CASE WHEN EXISTS (SELECT 1 FROM sys.index_columns ic JOIN sys.indexes x ON x.object_id = ic.object_id "
         "AND x.index_id = ic.index_id WHERE x.is_primary_key = 1 AND ic.object_id = c.object_id "
         "AND ic.column_id = c.column_id) THEN 1 ELSE 0 END FROM sys.columns c "
         "JOIN sys.types t ON t.user_type_id = c.user_type_id "
         f"WHERE c.object_id = OBJECT_ID(N'dbo.{table}') ORDER BY c.column_id")
    r = subprocess.run(['sqlcmd', '-S', server, '-E', '-d', db, '-b', '-h', '-1', '-W', '-s', '|', '-Q', q],
                       capture_output=True, text=True)
    if r.returncode:
        fail(f'sqlcmd failed reading dbo.{table}: {r.stderr.strip() or r.stdout.strip()}')
    rows = [line.split('|') for line in r.stdout.splitlines() if line.count('|') == 3]
    if not rows:
        fail(f'dbo.{table} has no columns: create the staging tables and views first')
    return [(n, t, lim, pk == '1') for n, t, lim, pk in rows]


def sql_table(table, cols, i='      '):
    body = ''
    for name, st, limit, pk in cols:
        if st not in SQLDB:
            fail(f'{table}.{name}: SQL type {st} has no mapping; cast it in the view')
        net, db = SQLDB[st]
        body += (f'{i}    <column type="Dynamicweb.DataIntegration.ProviderHelpers.SqlColumn" '
                 f'columnType="Dynamicweb.DataIntegration.ProviderHelpers.SqlColumn">\n'
                 f'{i}      <name>{escape(name)}</name>\n{i}      <type>{net}</type>\n{i}      <isNew>False</isNew>\n'
                 f'{i}      <limit>{limit}</limit>\n{i}      <isIdentity>False</isIdentity>\n'
                 f'{i}      <sqlDbType>{db}</sqlDbType>\n{i}      <isPrimaryKey>{"True" if pk else "False"}</isPrimaryKey>\n'
                 f'{i}    </column>\n')
    return (f'\n{i}<table>\n{i}  <isNew>False</isNew>\n{i}  <tableName>{table}</tableName>\n'
            f'{i}  <sqlSchema>dbo</sqlSchema>\n{i}  <foreignKeys />\n{i}  <columns>\n{body}{i}  </columns>\n{i}</table>\n    ')


def odata_node(tag, endpoint_id, schema):
    return (f'  <{tag} type="Dynamicweb.DataIntegration.Providers.ODataProvider.ODataProvider">\n'
            '    <Mode>Full Replication</Mode>\n    <Deltamodifier />\n    <Maximumpagesize>1000</Maximumpagesize>\n'
            '    <Requesttimeout>20</Requesttimeout>\n    <Runlastrequest>False</Runlastrequest>\n'
            '    <Requestintervals>0</Requestintervals>\n'
            '    <Donotstorelastresponseinlogfile>True</Donotstorelastresponseinlogfile>\n'
            f'    <Predefinedendpoint>{endpoint_id}</Predefinedendpoint>\n'
            f'    <Destinationendpoint>{endpoint_id}</Destinationendpoint>\n'
            '    <Continueonerror>False</Continueonerror>\n    <Failjobonendpointisbusy>True</Failjobonendpointisbusy>\n'
            f'    <SourceDecimalSeparator />\n    <Schema>{schema}</Schema>\n  </{tag}>\n')


def dw_node(tag, mirror, schema):
    return (f'  <{tag} type="Dynamicweb.DataIntegration.Providers.DynamicwebProvider.DynamicwebProvider">\n'
            '    <RemoveMissingRows>False</RemoveMissingRows>\n    <RemoveMissingAfterImport>False</RemoveMissingAfterImport>\n'
            f'    <RemoveMissingAfterImportDestinationTablesOnly>{mirror}</RemoveMissingAfterImportDestinationTablesOnly>\n'
            '    <DeactivateMissingProducts>False</DeactivateMissingProducts>\n'
            '    <UpdateOnlyExistingRecords>False</UpdateOnlyExistingRecords>\n'
            '    <InsertOnlyNewRecords>False</InsertOnlyNewRecords>\n    <DeleteIncomingItems>False</DeleteIncomingItems>\n'
            '    <Shop />\n    <DeleteProductsAndGroupForSpecificLanguage>False</DeleteProductsAndGroupForSpecificLanguage>\n'
            '    <DefaultLanguage>ENU</DefaultLanguage>\n    <RepositoriesIndexUpdate />\n'
            '    <DiscardDuplicates>False</DiscardDuplicates>\n    <HideDeactivatedProducts>False</HideDeactivatedProducts>\n'
            f'    <SkipFailingRows>False</SkipFailingRows>\n    <Schema>{schema}</Schema>\n  </{tag}>\n')


def mappings(src, src_schema, dst, dst_schema, cols, keys):
    body = ''.join(
        '        <columnMapping>\n          <scriptType />\n          <useCodeExtension>False</useCodeExtension>\n'
        f"          <isKey>{'True' if c in keys else 'False'}</isKey>\n          <isActive>True</isActive>\n"
        '          <scriptValueForInsert>False</scriptValueForInsert>\n'
        '          <nullEmptyActionType>None</nullEmptyActionType>\n          <nullEmptyActionValue />\n'
        f'          <sourceColumn>{escape(c)}</sourceColumn>\n          <destinationColumn>{escape(c)}</destinationColumn>\n'
        f'          <sort>{n + 1}</sort>\n        </columnMapping>\n' for n, c in enumerate(cols))
    ss = f'<sourceTableSchema>{src_schema}</sourceTableSchema>' if src_schema else '<sourceTableSchema />'
    ds = f'<destinationTableSchema>{dst_schema}</destinationTableSchema>' if dst_schema else '<destinationTableSchema />'
    # No empty <conditionals /> element: the loader drops the whole mapping when it meets one.
    return (f'  <mappings>\n    <mapping uid="{uuid.uuid4()}">\n      <isActive>True</isActive>\n'
            f'      <sourceTableName>{src}</sourceTableName>\n      {ss}\n'
            f'      <destinationTableName>{dst}</destinationTableName>\n      {ds}\n'
            '      <deleteRowsMissingFromSource>False</deleteRowsMissingFromSource>\n'
            '      <addColumnsFromSourceToMappingIfMissing>False</addColumnsFromSourceToMappingIfMissing>\n'
            f'      <scriptClass />\n      <columnMappings>\n{body}      </columnMappings>\n    </mapping>\n  </mappings>\n')


def job(name, desc, source, destination, maps):
    return ('<?xml version="1.0" encoding="utf-16"?>\n<job>\n'
            f'  <Name>{escape(name)}</Name>\n  <Description>{escape(desc)}</Description>\n'
            '  <asTransaction>True</asTransaction>\n  <CreateMappingAtRuntime>False</CreateMappingAtRuntime>\n'
            '  <DisableCacheClearingAndIndexUpdates>False</DisableCacheClearingAndIndexUpdates>\n'
            + source + destination + maps +
            '  <notificationSettings>\n    <FailureOnly>False</FailureOnly>\n  </notificationSettings>\n</job>\n')


def cmd_jobs(a):
    spec, ent = load_json(a.spec), load_json(a.entities)
    if '&' in spec['group']:
        fail("the activity group name carries '&': the MCP log lookup fails on it")
    server, db = connection(a)
    folder = Path(a.jobs) / spec['group']
    for s in spec.get('stage', []) + spec.get('export', []):
        if '&' in s['job']:
            fail(f"activity name {s['job']!r} carries '&'")
        check_columns(ent, s)
        keys = keys_of(ent, s)
        if 'table' in s:
            desc = f"Stage 1: F&O {s['entity']} -> staging {s['table']} (mirrored each run), endpoint {s['endpointId']}."
            src = odata_node('source', s['endpointId'], odata_table(ent, s['entity']))
            dst = dw_node('destination', 'True', sql_table(s['table'], sql_columns(server, db, s['table'])))
            maps = mappings(s['entity'], '', s['table'], 'dbo', s['cols'], keys)
        else:
            desc = f"Export: view {s['view']} -> F&O {s['entity']}, endpoint {s['endpointId']}."
            src = dw_node('source', 'False', sql_table(s['view'], sql_columns(server, db, s['view'])))
            dst = odata_node('destination', s['endpointId'], odata_table(ent, s['entity']))
            maps = mappings(s['view'], 'dbo', s['entity'], '', s['cols'], keys)
        path = folder / (s['job'] + '.xml')
        text = job(s['job'], s.get('description', desc), src, dst, maps)
        if not a.apply:
            print(f"would write {path}: {len(s['cols'])} columns, keys {keys}")
            continue
        folder.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf-16', newline='\r\n')   # UTF-16LE + BOM + CRLF, as the platform writes it
        raw = path.read_bytes()
        if raw[:2] != b'\xff\xfe' or raw.decode('utf-16').replace('\r\n', '\n') != text:
            fail(f'{path}: round-trip check failed')
        print(f"wrote {path}: {len(s['cols'])} columns, keys {keys}")
    if not a.apply:
        print('dry run: pass --apply to write the job files')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('entities')
    p.add_argument('--metadata', required=True)
    p.add_argument('--sets', required=True)
    p.add_argument('--out', required=True)
    p.set_defaults(f=cmd_entities)
    p = sub.add_parser('sql')
    p.add_argument('--spec', required=True)
    p.add_argument('--entities', required=True)
    p.add_argument('--out', required=True)
    p.set_defaults(f=cmd_sql)
    p = sub.add_parser('jobs')
    p.add_argument('--spec', required=True)
    p.add_argument('--entities', required=True)
    p.add_argument('--jobs', required=True)
    p.add_argument('--sql-server')
    p.add_argument('--database')
    p.set_defaults(f=cmd_jobs)
    for sp in sub.choices.values():
        sp.add_argument('--apply', action='store_true', help='write; without it the command is a dry run')
    a = ap.parse_args()
    a.f(a)


if __name__ == '__main__':
    main()
