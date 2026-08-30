// MediaGrammarProbe.java
// @category Analysis
// Corroborate the WMV script-stream grammar (CHESSBASE_MEDIA_RE.md):
// decompile the functions that reference the script-record strings.

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Data;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Reference;

public class MediaGrammarProbe extends GhidraScript {

    @Override
    public void run() throws Exception {
        DecompInterface decomp = new DecompInterface();
        decomp.openProgram(currentProgram);

        String[] needles = { "GA:", "Game Action", "V_ZOOM", "V_LASTMOVE",
                             "V_T_SQUARELIST", "V_T_IN_PB_AFTER",
                             "V_T_MOVE_MEDAL" };

        // defined-data string lookup (the proven path)
        java.util.HashMap<Address, String> strAddr =
            new java.util.HashMap<Address, String>();
        for (ghidra.program.model.listing.Data data
                : currentProgram.getListing().getDefinedData(true)) {
            String value = data.getDefaultValueRepresentation();
            if (value == null) continue;
            for (String needle : needles) {
                if (value.contains(needle)) {
                    strAddr.put(data.getAddress(), needle);
                    break;
                }
            }
        }
        println("### matched strings: " + strAddr.size());

        java.util.ArrayList<Address> done = new java.util.ArrayList<Address>();
        for (Address addr : strAddr.keySet()) {
            String what = strAddr.get(addr);
            println("=== " + what + " @ " + addr);
            for (Reference ref : getReferencesTo(addr)) {
                Function f = getFunctionContaining(ref.getFromAddress());
                if (f == null) continue;
                boolean dup = false;
                for (Address d : done) if (d.equals(f.getEntryPoint())) dup = true;
                if (dup) { println("  (already shown " + f.getName() + ")"); continue; }
                done.add(f.getEntryPoint());
                println("==== DECOMP " + f.getEntryPoint() + " " + f.getName()
                        + " (ref @ " + ref.getFromAddress() + ") ====");
                DecompileResults res = decomp.decompileFunction(f, 120, monitor);
                if (res != null && res.getDecompiledFunction() != null) {
                    String c = res.getDecompiledFunction().getC();
                    if (c.length() > 14000) c = c.substring(0, 14000) + "\n...TRUNC";
                    println(c);
                } else {
                    println("  decompile failed");
                }
            }
        }
        decomp.dispose();
    }
}