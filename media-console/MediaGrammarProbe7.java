// MediaGrammarProbe7.java
// @category Analysis
// Q2 + Q3: marker STYLE bytes 2/3/4 colors (opcode-06 type-4/5 squarelist
// records) and type-7 (00 index square 00) semantics.
//
//  1) String-driven hunt: every function referencing V_T_SQUARELIST /
//     V_B_SQUARELIST / V_T_COLOR / V_B_COLOR / V_MAP / V_MOVES /
//     V_LASTMOVE / V_ZOOM.  The statistics dialogs already decompiled in
//     probe 1 (FUN_1406d9720, FUN_1406d7a70) and FUN_14079bec0 are skipped;
//     new referencers (renderer/edit path) are decompiled.
//  2) PARAMETRIC: fill TARGETS after MediaGrammarProbe6 names the GA
//     consumer's opcode-6 record switch (type-4/5 squarelist handler,
//     type-7 handler).  Decompile each.
//  3) Palette scan: byte scan of non-executable blocks for classic
//     COLORREF triples (pure + dark green/red/yellow/blue) as a stand-in
//     for the python exe grep; prints candidate addresses + 12 dwords.

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Data;
import ghidra.program.model.listing.Function;
import ghidra.program.model.mem.Memory;
import ghidra.program.model.mem.MemoryBlock;
import ghidra.program.model.symbol.Reference;
import java.util.ArrayList;

public class MediaGrammarProbe7 extends GhidraScript {

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
        Memory mem = currentProgram.getMemory();

        // ---------------------------------------------------------------
        println("### 1) V_T_* string referencers (renderer hunt)");
        String[] needles = { "V_T_SQUARELIST", "V_B_SQUARELIST", "V_T_COLOR",
                             "V_B_COLOR", "V_MAP", "V_MOVES", "V_LASTMOVE",
                             "V_ZOOM", "V_T_PIECE_PATH", "V_T_PAWN_STRUCTURE" };
        // known dialog/stat functions from probe 1 — skip these
        long[] skip = { 0x1406d9720L, 0x1406d7a70L, 0x14079bec0L,
                        0x1406d9430L, 0x1406d9000L, 0x1406d6920L,
                        0x1406d7040L };
        ArrayList<Address> done = new ArrayList<Address>();
        for (Data data : currentProgram.getListing().getDefinedData(true)) {
            String value = data.getDefaultValueRepresentation();
            if (value == null) continue;
            String hit = null;
            for (String n : needles) {
                // exact token match to avoid V_MAP matching inside others
                String v = value.replace("\"", "").trim();
                if (v.equals(n)) { hit = n; break; }
            }
            if (hit == null) continue;
            println("=== " + hit + " @ " + data.getAddress());
            for (Reference ref : getReferencesTo(data.getAddress())) {
                Function f = getFunctionContaining(ref.getFromAddress());
                if (f == null || done.contains(f.getEntryPoint())) continue;
                boolean sk = false;
                for (long s : skip) {
                    if (f.getEntryPoint().equals(toAddr(s))) { sk = true; break; }
                }
                if (sk) { println("  (skip known " + f.getName() + ")"); continue; }
                done.add(f.getEntryPoint());
                println("  ref @ " + ref.getFromAddress());
                dump(decomp, f, 45000);
            }
        }

        // ---------------------------------------------------------------
        println("### 2) parametric targets (fill from Probe 6 output)");
        long[] targets = {
            // e.g. 0x140xxxxxxL  // opcode-06 record switch (GA consumer +0x480)
            // e.g. 0x140xxxxxxL  // type-4/5 squarelist handler
            // e.g. 0x140xxxxxxL  // type-7 handler
        };
        for (long t : targets) {
            Function f = getFunctionAt(toAddr(t));
            if (f == null) { println("MISSING fn @ " + Long.toHexString(t)); continue; }
            dump(decomp, f, 60000);
        }

        // ---------------------------------------------------------------
        println("### 3) COLORREF palette scan (.rdata/.data)");
        // little-endian dword patterns for pure/dark green red yellow blue
        int[][] pals = {
            { 0x0000FF00, 0x000000FF, 0x0000FFFF },  // green red yellow
            { 0x00008000, 0x00000080, 0x00008080 },  // dark green/red/yellow
        };
        for (MemoryBlock blk : mem.getBlocks()) {
            if (blk.isExecute() || !blk.isInitialized()) continue;
            long size = blk.getSize();
            if (size > 0x2000000) continue;
            byte[] all = new byte[(int) size];
            int n;
            try { n = blk.getBytes(blk.getStart(), all); }
            catch (Exception ex) { continue; }
            int hits = 0;
            for (int i = 0; i + 12 <= n; i += 4) {
                for (int p = 0; p < pals.length; p++) {
                    int b0 = all[i] & 0xff, b1 = all[i + 1] & 0xff,
                        b2 = all[i + 2] & 0xff, b3 = all[i + 3] & 0xff;
                    int v0 = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
                    if (v0 != pals[p][0]) continue;
                    // require one of the other palette colors within 32 bytes
                    boolean near = false;
                    for (int j = i + 4; j <= i + 32 && j + 4 <= n; j += 4) {
                        int w = (all[j] & 0xff) | ((all[j + 1] & 0xff) << 8)
                              | ((all[j + 2] & 0xff) << 16) | ((all[j + 3] & 0xff) << 24);
                        if (w == pals[p][1] || w == pals[p][2]) { near = true; break; }
                    }
                    if (!near) continue;
                    Address ha = blk.getStart().add((long) i);
                    StringBuilder sb = new StringBuilder();
                    sb.append("PALETTE ").append(p == 0 ? "pure" : "dark")
                      .append(" @ ").append(ha).append(" in ").append(blk.getName()).append(":");
                    for (int j = i; j <= i + 44 && j + 4 <= n; j += 4) {
                        int w = (all[j] & 0xff) | ((all[j + 1] & 0xff) << 8)
                              | ((all[j + 2] & 0xff) << 16) | ((all[j + 3] & 0xff) << 24);
                        sb.append(String.format(" %08x", w));
                    }
                    println(sb.toString());
                    // show referencing functions, if any
                    for (Reference ref : getReferencesTo(ha)) {
                        Function f = getFunctionContaining(ref.getFromAddress());
                        if (f != null) println("    referenced by " + f.getEntryPoint()
                                               + " " + f.getName());
                    }
                    if (++hits >= 40) break;
                }
                if (hits >= 40) break;
            }
        }

        decomp.dispose();
    }
}
