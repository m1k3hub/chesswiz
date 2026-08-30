// FindChessBaseMediaRefs.java
// @category Analysis
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Data;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Reference;

public class FindChessBaseMediaRefs extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] needles = {"ScriptItems", "ScriptActivationManager",
                "Chess Media System", "Extra Chess Media", "Audio Stream"};
        String[] callbackNeedles = {"IWMReaderCallback", "IWMReaderCallbackAdvanced"};
        for (Data data : currentProgram.getListing().getDefinedData(true)) {
            String value = data.getDefaultValueRepresentation();
            if (value == null) continue;
            for (String needle : concat(needles, callbackNeedles)) {
                if (!value.contains(needle)) continue;
                Address address = data.getAddress();
                println("STRING " + address + " " + value);
                for (Reference ref : getReferencesTo(address)) {
                    Function function = getFunctionContaining(ref.getFromAddress());
                    println("  REF " + ref.getFromAddress() + " "
                            + (function == null ? "<none>" : function.getName()));
                }
                break;
            }
        }
    }

    private String[] concat(String[] first, String[] second) {
        String[] result = new String[first.length + second.length];
        System.arraycopy(first, 0, result, 0, first.length);
        System.arraycopy(second, 0, result, first.length, second.length);
        return result;
    }
}
