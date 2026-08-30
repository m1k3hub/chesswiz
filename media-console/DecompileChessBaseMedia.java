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
                "140549080", "14101f200", "14101f2b0",
                "140d7b530", "140d7c9c0", "140d7d8b0",
                "140fb3dc6", "1405b4880", "1405b4bc0",
                "1405b4eb0", "1405b49b0",
                "0054ae3e", "006291bb"};

        for (String text : targets) {
            Address address = toAddr(text);
            if (address == null) {
                println("MISSING " + text);
                continue;
            }
            Function f = getFunctionAt(address);
            if (f == null) f = getFunctionContaining(address);
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
