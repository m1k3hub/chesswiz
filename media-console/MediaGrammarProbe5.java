// MediaGrammarProbe5.java
// @category Analysis
// Follow the script-item construction chain upward: decompile callers of
// the ScriptItem ctor and the MA-dispatcher.

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Reference;

public class MediaGrammarProbe5 extends GhidraScript {

    private void dump(Function f, DecompInterface decomp, int limit) {
        println("==== DECOMP " + f.getEntryPoint() + " " + f.getName() + " ====");
        DecompileResults res = decomp.decompileFunction(f, 150, monitor);
        if (res != null && res.getDecompiledFunction() != null) {
            String c = res.getDecompiledFunction().getC();
            if (c.length() > limit) c = c.substring(0, limit) + "\n...TRUNC";
            println(c);
        } else {
            println("  decompile failed");
        }
    }

    @Override
    public void run() throws Exception {
        DecompInterface decomp = new DecompInterface();
        decomp.openProgram(currentProgram);

        Object[][] targets = {
            { 0x1403abbe0L, "ScriptItem ctor" },
            { 0x1403a78e0L, "MA handler" },
            { 0x1403a88a0L, "MA/GA/TEXT dispatcher" },
        };
        for (Object[] tt : targets) {
            Object t0 = tt[0];
            long addrVal = ((Number) t0).longValue();
            Address addr = toAddr(addrVal);
            Function f = getFunctionAt(addr);
            if (f == null) { println("MISSING " + addrVal); continue; }
            println("### about " + tt[1] + " = " + f.getName());
            int done = 0;
            for (Reference ref : getReferencesTo(addr)) {
                Function caller = getFunctionContaining(ref.getFromAddress());
                if (caller == null) continue;
                if (caller.getEntryPoint().equals(addr)) continue;
                println(">>> CALLER " + caller.getEntryPoint() + " " + caller.getName()
                        + " (call @ " + ref.getFromAddress() + ")");
                dump(caller, decomp, 24000);
                if (++done >= 4) break;
            }
        }
        decomp.dispose();
    }
}