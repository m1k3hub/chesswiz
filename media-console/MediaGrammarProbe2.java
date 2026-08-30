// MediaGrammarProbe2.java
// @category Analysis
// Follow the script-item export path: decompile the callers of the
// column formatter and the sequence getter.

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Reference;

public class MediaGrammarProbe2 extends GhidraScript {

    private void dump(Function f, DecompInterface decomp, int limit) {
        println("==== DECOMP " + f.getEntryPoint() + " " + f.getName() + " ====");
        DecompileResults res = decomp.decompileFunction(f, 120, monitor);
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

        // the column formatter and the sequence getter
        long[] targets = { 0x1403ac210L, 0x1403ac000L };
        for (long t : targets) {
            Address addr = toAddr(t);
            Function f = getFunctionAt(addr);
            if (f == null) {
                println("MISSING " + Long.toHexString(t));
                continue;
            }
            println("### SELFM " + f.getName());
            dump(f, decomp, 8000);
            // direct callers
            for (Reference ref : getReferencesTo(addr)) {
                Function caller = getFunctionContaining(ref.getFromAddress());
                if (caller == null) continue;
                println(">>> CALLER " + caller.getEntryPoint() + " " + caller.getName()
                        + " (call @ " + ref.getFromAddress() + ")");
                dump(caller, decomp, 16000);
            }
        }
        decomp.dispose();
    }
}