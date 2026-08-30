// @category Analysis
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;

public class DecompileChessBaseMedia extends GhidraScript {
    @Override
    public void run() throws Exception {
        DecompInterface decomp = new DecompInterface();
        decomp.openProgram(currentProgram);
        String[] targets = {"1407bd3d0", "1407ae660", "1403ac3b0",
                "140549080", "14101f200", "14101f2b0"};
        for (String text : targets) {
            Function f = getFunctionAt(toAddr(text));
            if (f == null) {
                println("MISSING " + text);
                continue;
            }
            DecompileResults result = decomp.decompileFunction(f, 120, monitor);
            println("===== " + f.getEntryPoint() + " " + f.getName() + " =====");
            println(result.getDecompiledFunction() == null
                    ? result.getErrorMessage()
                    : result.getDecompiledFunction().getC());
        }
        decomp.dispose();
    }
}
