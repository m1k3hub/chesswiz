// MediaGrammarProbe8.java
// @category Analysis
// Context probe: the MA handler, the +0x252 reset path, the post-dispatch
// board update, and the dispatcher caller chain.  Everything here is one
// hop away from the GA consumer and names the surrounding object graph.

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Reference;
import java.util.ArrayList;

public class MediaGrammarProbe8 extends GhidraScript {

    private void dump(DecompInterface decomp, Function f, int limit) {
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
            { 0x1403a78e0L, "MA handler",                60000 },
            { 0x1403a8450L, "+0x252 reset path",         30000 },
            { 0x14039d870L, "post-dispatch board update",30000 },
        };
        for (Object[] tt : targets) {
            Address addr = toAddr(((Number) tt[0]).longValue());
            Function f = getFunctionAt(addr);
            if (f == null) { println("MISSING " + tt[0]); continue; }
            println("### " + tt[1] + " = " + f.getName());
            dump(decomp, f, (Integer) tt[2]);
        }

        // callers of the timer dispatcher (window proc chain)
        println("### callers of dispatcher FUN_1403a88a0");
        ArrayList<Address> done = new ArrayList<Address>();
        int n = 0;
        for (Reference ref : getReferencesTo(toAddr(0x1403a88a0L))) {
            Function f = getFunctionContaining(ref.getFromAddress());
            if (f == null || done.contains(f.getEntryPoint())) continue;
            done.add(f.getEntryPoint());
            println(">>> CALLER " + f.getEntryPoint() + " " + f.getName());
            if (!f.getEntryPoint().equals(toAddr(0x1403a8f60L))) {
                dump(decomp, f, 40000);   // FUN_1403a8f60 already archived
            } else {
                println("  (FUN_1403a8f60 already decompiled in probe 3/5 logs)");
            }
            if (++n >= 6) break;
        }

        // callers of the second dispatcher (who issues QUEUE/COMMAND items)
        println("### callers of second dispatcher FUN_1403a8590");
        n = 0;
        for (Reference ref : getReferencesTo(toAddr(0x1403a8590L))) {
            Function f = getFunctionContaining(ref.getFromAddress());
            if (f == null || done.contains(f.getEntryPoint())) continue;
            done.add(f.getEntryPoint());
            println(">>> CALLER " + f.getEntryPoint() + " " + f.getName());
            dump(decomp, f, 40000);
            if (++n >= 6) break;
        }

        decomp.dispose();
    }
}
