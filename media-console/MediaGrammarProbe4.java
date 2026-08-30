// MediaGrammarProbe4.java
// @category Analysis
// Find the six-bit transport decoder: locate the 0x3f..0x7e alphabet
// table in memory and decompile the referencing functions.

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.mem.MemoryBlock;
import ghidra.program.model.symbol.Reference;

import ghidra.program.model.listing.Function;

public class MediaGrammarProbe4 extends GhidraScript {

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

        // scan every writable/readonly block for the six-bit alphabet table
        byte[] table = new byte[64];
        for (int i = 0; i < 64; i++) table[i] = (byte) (0x3F + i);

        for (MemoryBlock blk : currentProgram.getMemory().getBlocks()) {
            long size = blk.getSize();
            if (size > 0x10000000) continue;
            byte[] all = new byte[(int) size];
            int n = all.length;
            try {
                n = blk.getBytes(blk.getStart(), all);
            } catch (Exception ex) {
                continue;
            }
            for (int i = 0; i + 64 <= n; i++) {
                if (all[i] == 0x3F && all[i + 1] == 0x40 && all[i + 2] == 0x41
                        && all[i + 63] == 0x7E) {
                    Address ta = blk.getStart().add((long) i);
                    println("### six-bit table @ " + ta + " in " + blk.getName());
                    int shown = 0;
                    for (Reference ref : getReferencesTo(ta)) {
                        Function f = getFunctionContaining(ref.getFromAddress());
                        if (f == null) continue;
                        dump(f, decomp, 16000);
                        if (++shown >= 3) break;
                    }
                }
            }
        }
        decomp.dispose();
    }
}