// MediaGrammarProbe9.java
// @category Analysis
// Final layer of the GA wire grammar: the record parser, the record->text
// formatter (opcode dictionary), the kernel apply functions, the QUERY
// handler, the media-ctor tail (consumer assignment site), and the
// encrypted-stream path.
//
// From probes 6-8:
//   consumer = CBaseGameKernel-family object at MediaPlayerWin+0x248;
//   +0x480 = FUN_1409f0cd0  -> decode FUN_140f20e40 (GA/GC mode1 six-bit,
//      TEXT mode0 decimal-len+hex) -> parse FUN_140da2160 -> apply
//      FUN_1409f09c0 (per window), watch variant FUN_140daace0,
//      replay-export FUN_140da1650; sequence print FUN_140da1d70.
//
// These bodies contain the opcode-2/3/4/6/8/14/15 dispatch and the
// opcode-4 class/modifier visual mapping, the squarelist style colors,
// and the type-7 record handling.

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import java.util.ArrayList;

public class MediaGrammarProbe9 extends GhidraScript {

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
            { 0x140da2160L, "GA record PARSER (opcode switch)",        70000 },
            { 0x140da1d70L, "GA record -> text (Sequence col)",        45000 },
            { 0x1409f09c0L, "kernel APPLY record to window",           70000 },
            { 0x140daace0L, "watch-window apply",                      30000 },
            { 0x140da1650L, "record -> replay-export form",            20000 },
            { 0x1409f1480L, "consumer +0x490 QUERY handler",           20000 },
            { 0x1403a35b0L, "MediaPlayerWin ctor tail (+0x248 setup)", 25000 },
            { 0x140f21150L, "crypt buf init (0xc0)",                   15000 },
            { 0x140f21fa0L, "crypt buf feed",                          15000 },
            { 0x140f22940L, "crypt buf finalize/decrypt",              15000 },
        };
        for (Object[] tt : targets) {
            Address addr = toAddr(((Number) tt[0]).longValue());
            Function f = getFunctionAt(addr);
            if (f == null) { println("MISSING " + tt[0] + " " + tt[1]); continue; }
            println("### " + tt[1] + " = " + f.getName());
            dump(decomp, f, (Integer) tt[2]);
        }

        // callees of the apply function: the per-opcode board actions
        println("### callees of FUN_1409f09c0 (per-opcode actions)");
        Function apply = getFunctionAt(toAddr(0x1409f09c0L));
        if (apply != null) {
            int n = 0;
            ArrayList<Address> seen = new ArrayList<Address>();
            for (Function c : apply.getCalledFunctions(monitor)) {
                if (c == null || seen.contains(c.getEntryPoint())) continue;
                seen.add(c.getEntryPoint());
                println(">>> APPLY CALLS " + c.getEntryPoint() + " " + c.getName());
                dump(decomp, c, 18000);
                if (++n >= 8) break;
            }
        }

        decomp.dispose();
    }
}
