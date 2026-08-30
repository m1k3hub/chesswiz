// @category Analysis
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.mem.MemoryBlock;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Reference;
import java.nio.charset.StandardCharsets;

public class FindRawChessBaseMediaRefs extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] needles = {"ScriptItems", "Chess Media System",
                "IWMReaderCallback", "IWMReaderCallbackAdvanced"};
        for (MemoryBlock block : currentProgram.getMemory().getBlocks()) {
            if (!block.isInitialized() || block.getSize() > Integer.MAX_VALUE) continue;
            byte[] bytes = new byte[(int) block.getSize()];
            block.getBytes(block.getStart(), bytes);
            for (String needle : needles) {
                byte[] wanted = needle.getBytes(StandardCharsets.US_ASCII);
                for (int at = indexOf(bytes, wanted, 0); at >= 0;
                        at = indexOf(bytes, wanted, at + 1)) {
                    Address address = block.getStart().add(at);
                    println("RAW " + address + " " + needle);
                    for (int delta = 0; delta >= -24; delta -= 4) {
                        for (Reference ref : getReferencesTo(address.add(delta))) {
                            Function f = getFunctionContaining(ref.getFromAddress());
                            println("  REF " + ref.getFromAddress() + " target="
                                    + address.add(delta) + " " + (f == null ? "<none>"
                                    : f.getEntryPoint() + " " + f.getName()));
                        }
                    }
                }
            }
        }
    }

    private int indexOf(byte[] bytes, byte[] wanted, int start) {
        outer: for (int i = start; i <= bytes.length - wanted.length; i++) {
            for (int j = 0; j < wanted.length; j++) {
                if (bytes[i + j] != wanted[j]) continue outer;
            }
            return i;
        }
        return -1;
    }
}
