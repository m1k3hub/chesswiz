import os, pathlib, re, subprocess, tempfile, time, json
root=pathlib.Path.cwd()
out=root/'tests/tmp-app/cmdline/review'
review=(out/'REREVIEW2.md').read_text()
suites=[]
for n, filename in re.findall(r'^\| (\d+) \| `([^`]+\.tcl)` \|', review, re.M):
    n=int(n)
    if n <= 45: mode='app'
    elif n <= 47: mode='tclsh'
    else: mode='engine'
    suites.append((filename,mode))
assert len(suites)==48, suites
results=json.loads((out/"fix3_serial_results.json").read_text()) if (out/"fix3_serial_results.json").exists() else []
results=[r for r in results if r["valid"] and not r["exit"] and not r["failed"]]
for index,(filename,mode) in enumerate(suites,1):
    if index <= len(results): continue
    log=out/f'fix3_serial_{mode}_{filename[:-4]}.log'
    with tempfile.TemporaryDirectory(prefix='cw-fix3-') as home:
        env=dict(os.environ,HOME=home,PULSE_SINK='cwtests')
        if mode=='tclsh': cmd=['timeout','900','tclsh','tests/run_all.tcl','-file',filename]
        else:
            cmd=['timeout','900','xvfb-run','-a','-s','-screen 0 1920x1080x24','src/tkchesswiz']
            cmd+=['tests/'+filename] if mode=='engine' else ['tests/run_app_tests.tcl','-file',filename]
        if filename=='test_app_action_reachability.tcl':
            # The optional UI sweep opens Lichess panels that fetch public
            # data. Keep its four non-UI checks; do not run that sweep.
            cmd+=['-match','reachability-startup reachability-registry reachability-references reachability-explicit-gates']
        print(f'{index}/48 START {mode} {filename}',flush=True)
        start=time.monotonic()
        with log.open('w') as stream:
            proc=subprocess.run(cmd,env=env,stdin=subprocess.DEVNULL,stdout=stream,stderr=subprocess.STDOUT)
        data=log.read_text(errors='replace')
        if mode=='engine':
            passed=len(re.findall(r'^PASS:',data,re.M))
            failed=len(re.findall(r'^FAIL:',data,re.M))
            skipped=0
            valid='AI-ENGINE-FAILURES: 0' in data
        else:
            counts=[re.findall(r'Total '+key+r': (\d+)',data) for key in ['Passed','Failed','Skipped']]
            valid=all(counts)
            passed,failed,skipped=[int(c[-1]) if c else -1 for c in counts]
        result=dict(suite=filename,mode=mode,passed=passed,failed=failed,skipped=skipped,exit=proc.returncode,valid=bool(valid),seconds=round(time.monotonic()-start,2),log=log.name)
        results.append(result)
        (out/'fix3_serial_results.json').write_text(json.dumps(results,indent=2)+'\n')
        print(f'{index}/48 DONE {result}',flush=True)
        if proc.returncode or failed or not valid:
            print('STOP: investigate failed run before continuing',flush=True)
            break
