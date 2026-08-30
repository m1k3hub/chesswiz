// MediaGrammarProbe3.java
// @category Analysis
// Scan .rdata for the action-name literals "GA\0" and "TEXT\0", then
// decompile the functions that reference them.

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.mem.MemoryBlock;
import ghidra.program.model.listing.Data;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Reference;

public class MediaGrammarProbe3 extends GhidraScript {

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

        MemoryBlock block = currentProgram.getMemory().getBlock(toAddr(0x1411804f4L));
        long bsize = block.getSize();
        println("### scanning block " + block.getName() + " " + bsize + " bytes");
        byte[] all = new byte[(int) bsize];
        block.getBytes(block.getStart(), all);

        byte[] ga = "GA\u0000".getBytes("latin1");
        byte[] txt = "TEXT\u0000".getBytes("latin1");

        java.util.ArrayList<long[]> cand = new java.util.ArrayList<long[]>();
        for (int i = 0; i + 5 <= all.length; i++) {
            if (all[i] == 'G' && all[i + 1] == 'A' && all[i + 2] == 0) {
                cand.add(new long[] { block.getStart().getOffset() + i, 0 });
            }
            if (all[i] == 'T' && all[i + 1] == 'E' && all[i + 2] == 'X'
                && all[i + 3] == 'T' && all[i + 4] == 0) {
                cand.add(new long[] { block.getStart().getOffset() + i, 1 });
            }
        }
        println("### GA/TEXT literals in .rdata: " + cand.size());

        int shown = 0;
        for (long[] c : cand) {
            Address addr = toAddr(c[0]);
            String tag = c[1] == 0 ? "GA" : "TEXT";
            for (Reference ref : getReferencesTo(addr)) {
                Function f = getFunctionContaining(ref.getFromAddress());
                if (f == null) continue;
                println("=== " + tag + " @ " + addr + " referenced by "
                        + f.getEntryPoint() + " " + f.getName() + " @ "
                        + ref.getFromAddress());
                dump(f, decomp, 16000);
                if (++shown >= 6) break;
            }
            if (shown >= 6) break;
        }
        // the transpose table slice
        int tstart = -1;
        for (int i = 0; i + 8 <= all.length; i++) {
            if ((all[i] == 0x20 && all[i + 1] == 0x28 && all[i + 2] == 0x30
                 && all[i + 3] == 0x38 && all[i + 4] == 0x01 && all[i + 5] == 0x09
                 && all[i + 6] == 0x11 && all[i + 7] == 0x19)) {
                tstart = i - 4;
                break;
            }
        }
        if (tstart >= 0) {
            Address taddr = toAddr(block.getStart().getOffset() + tstart);
            println("### transpose table @ " + taddr);
            for (Reference ref : getReferencesTo(taddr)) {
                Function f = getFunctionContaining(ref.getFromAddress());
                if (f == null) continue;
                dump(f, decomp, 16000);
            }
        } else {
            println("### transpose not present in .rdata block");
        }
        decomp.dispose();
    }
}